pragma solidity ^0.5.2;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./SafeMathInt.sol";
import "./UsdToken.sol";
import "./IOracle.sol";

// Any account can create a CDP by deposting ETH and minting USD tokens
// USD tokens can only be minted up to the collateralisation ratio
// If a CDP  falls below the liquidation ratio (e.g. ETH / USD falls) then the CDP goes up for auction
// Once the CDP auction completes any credit / deficit is socialised across all USD CDP issuances
// For example, if a CDP owes 200 USD and the auction only raises 150 USD, then a small amount is added to every CDPs USD deficit, proportionally to their USD drawdowns, such that the sum is 50 USD.
// If a CDP owes 100 USD and the auction raises 200 USD, then 100 USD is debited from all CDP USD deficits proportionally to USD drawdowns.

// Some assumptions to simplify accounting:
// 1. Once an account has been liquidated it can no longer interact with the system
// 2. When a CDP is being auctioned, each account can only bid once per CDP

contract SocialisedCdp {
    using SafeMath for uint256;
    using SafeMathInt for int256;

    // Ratio at which USD tokens can be drawn against ETH collateral
    uint256 public constant collateralRatio = 66*10**16;
    // Ratio after which CDP can be liquidated
    uint256 public constant liquidationRatio = 90*10**16;

    // Oracle to use for USD / ETH prices
    IOracle public oracle;
    // USD stable coin
    UsdToken public usdToken;
    // Total outstanding Usd debt
    uint256 public outstandingUsd;

    // ETH deposited
    mapping (address => uint256) public ethCollateral;
    // USD withdrawn through usdToken
    mapping (address => uint256) public usdWithdrawn;
    // +ve / -ve correction for usdWithdrawn based on liquidations
    mapping (address => int256) public usdCorrections;

    // Mapping from CDP to best bid on that CDP
    mapping (address => uint256) public bestBid;
    // Mapping from CDP to bidders and their submitted bids
    mapping (address => mapping (address => uint256)) public submittedBids;
    // Mapping from CDP to bidder with current highest bid
    mapping (address => address) public winningBidder;
    // Mapping from CDP to start time of CDP liquidation auction
    mapping (address => uint256) public bidStart;
    // Length of a CDP auction
    uint256 public auctionLength = 0; //60 * 60; // 1 hour

    // Used to manage dust when distributing liquidation "dividends"
    int256 constant internal magnitude = 2**128;
    // Correction (per USD) from liquidation "dividends"
    int256 public correctionPerUsd;

    constructor (address _oracle, address _usdToken) public {
        /* collateralRatio = _collateralRatio;
        liquidationRatio = _liquidationRatio; */
        oracle = IOracle(_oracle);
        usdToken = UsdToken(_usdToken);
    }

    // Distributes +ve / -ve credits from liquidations
    // +ve: a credit (i.e. liquidation happened above debt owed)
    // -ve: a debit (i.e. liquidation didn't cover debt owed)
    function _manageCredit(int256 _amount) internal {
        if (_amount == 0) return;
        require(outstandingUsd > 0);
        if (_amount >= 0) {
            correctionPerUsd = correctionPerUsd.add(
              _amount.mul(magnitude) / _toInt256(outstandingUsd)
            );
        } else {
            correctionPerUsd = correctionPerUsd.sub(
              _amount.mul(magnitude) / _toInt256(outstandingUsd)
            );
        }
    }

    // Calculate amount of credit for a particular account (CDP)
    function accumulatedCredit(address _account) public view returns (int256) {
        return correctionPerUsd.mul(_toInt256(usdWithdrawn[_account]))
            .add(usdCorrections[_account]) / magnitude;
    }

    // Total USD owed to the CDP from combined drawndowns and credits
    function totalUsdOwed(address _account) public view returns (uint256) {
        if (accumulatedCredit(_account) >= 0) {
            return usdWithdrawn[_account].sub(_toUint256(accumulatedCredit(_account)));
        } else {
            return usdWithdrawn[_account].add(_toUint256(accumulatedCredit(_account)));
        }
    }

    function depositEth() payable external {
        //Don't allow deposits on accounts that have been liquidated
        require(bidStart[msg.sender] == 0);
        ethCollateral[msg.sender] += msg.value;
    }

    function depositUsd(uint256 _amount) external {
        //Don't allow deposits on accounts that have been liquidated
        require(bidStart[msg.sender] == 0);
        //Will revert if transfer fails, or we try and pay back more than we've borrowed
        usdWithdrawn[msg.sender] = usdWithdrawn[msg.sender].sub(_amount);
        _burn(msg.sender, _amount);
    }

    function withdrawEth(uint256 _amount) external {
        //Don't allow withdrawals on accounts that have been liquidated
        require(bidStart[msg.sender] == 0);
        ethCollateral[msg.sender] = ethCollateral[msg.sender].sub(_amount);
        require(_checkLiquidity(msg.sender));
    }

    function withdrawUsd(uint256 _amount) external {
        //Don't allow withdrawals on accounts that have been liquidated
        require(bidStart[msg.sender] == 0);
        usdWithdrawn[msg.sender] = usdWithdrawn[msg.sender].add(_amount);
        require(_checkLiquidity(msg.sender));
        _mint(msg.sender, _amount);
    }

    function bidMarginCall(address _account, uint256 _amount) external {
        //Check that an auction has already started and not ended
        //or that _checkLiquidity(_account) is true
        //Lock _bid value in USD tokens and record bid
        require(!_checkLiquidity(_account) || bidStart[_account] > 0);
        if (bidStart[_account] == 0) {
            bidStart[_account] = now;
        }
        require(bidStart[_account].add(auctionLength) >= now);
        //Only one bid per address for simplicity
        require(submittedBids[_account][msg.sender] == 0);
        require(_amount > bestBid[_account]);
        submittedBids[_account][msg.sender] = _amount;
        bestBid[_account] = _amount;
        winningBidder[_account] = msg.sender;
        require(usdToken.transferFrom(msg.sender, address(this), _amount));
    }

    function executeMarginCall(address _account) external {
        require(winningBidder[_account] == msg.sender);
        require(submittedBids[_account][msg.sender] > 0);
        require(bidStart[_account].add(auctionLength) < now);

        // Calculate liquidity difference
        int256 credit = _toInt256(submittedBids[_account][msg.sender]).sub(_toInt256(totalUsdOwed(_account)));
        msg.sender.transfer(ethCollateral[_account]);
        require(usdToken.burnFrom(address(this), submittedBids[_account][msg.sender]));
        outstandingUsd = outstandingUsd.sub(totalUsdOwed(_account));
        submittedBids[_account][msg.sender] = 0;
        ethCollateral[_account] = 0;
        usdWithdrawn[_account] = 0;
        _manageCredit(credit);
    }

    function refundMarginCall(address _account) external {
        require(winningBidder[_account] != msg.sender);
        require(usdToken.transfer(msg.sender, submittedBids[_account][msg.sender]));
        submittedBids[_account][msg.sender] = 0;
    }

    function _checkLiquidity(address _account) public view returns (bool) {
        //Check whether account is still liquid
        uint256 usdValueOfEth = ethCollateral[_account].mul(_getUsdPrice()).div(10**18);
        return usdValueOfEth.mul(liquidationRatio).div(10**18) >= totalUsdOwed(_account);
    }

    function _availableCredit(address _account) public view returns (uint256) {
        //Throws if credit < 0;
        uint256 usdValueOfEth = ethCollateral[_account].mul(_getUsdPrice()).div(10**18);
        return usdValueOfEth.mul(liquidationRatio).div(10**18).sub(totalUsdOwed(_account));
    }

    function _getUsdPrice() internal view returns (uint256) {
        return oracle.getPrice();
    }

    function _mint(address _account, uint256 _amount) internal {
        require(usdToken.mint(_account, _amount));
        usdCorrections[_account] = usdCorrections[_account]
          .sub(correctionPerUsd.mul(_toInt256(_amount)));
        outstandingUsd = outstandingUsd.add(_amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(usdToken.burnFrom(_account, _amount));
        usdCorrections[_account] = usdCorrections[_account]
          .add(correctionPerUsd.mul(_toInt256(_amount)));
        outstandingUsd = outstandingUsd.sub(_amount);
    }

    function _toInt256(uint256 a) internal pure returns (int256) {
        int256 b = int256(a);
        require(b >= 0);
        return b;
    }

    function _toUint256(int256 a) internal pure returns (uint256) {
        if (a >= 0) {
            return uint256(a);
        } else {
            return uint256(-a);
        }
    }

}
