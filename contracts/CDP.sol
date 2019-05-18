pragma solidity ^0.5.2;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./SafeMathInt.sol";
import "./UsdToken.sol";
import "./IOracle.sol";

contract CDP {
    using SafeMath for uint256;
    using SafeMathInt for int256;

    // Oracle to use for USD / ETH prices
    IOracle public oracle;

    // Issued USD stable coin
    UsdToken public usdToken;

    // ETH deposited
    mapping (address => uint256) public ethCollateral;
    // USD withdrawn
    mapping (address => uint256) public usdWithdrawn;

    // Mapping from CDP to best bid on that CDP
    mapping (address => uint256) public bestBid;

    // Mapping from CDP to bidders and their submitted bids
    mapping (address => mapping (address => uint256)) public submittedBids;

    mapping (address => address) public winningBidder;

    mapping (address => uint256) public bidStart;

    uint256 public collateralRatio = 66*10**16; //percentage multiplied by 10^16 - i.e. 100% = 10^18
    uint256 public liquidationRatio = 90*10**16; //percentage multiplied by 10^16 - i.e. 100% = 10^18

    uint256 public auctionLength = 60 * 60; // 1 hour

    int256 constant internal magnitude = 2**128;

    int256 public magnifiedCreditPerUsd;

    mapping(address => int256) public magnifiedCreditCorrections;
    /* mapping(address => uint256) internal withdrawnDividends; */

    constructor (address _oracle, address _usdToken) public {
        /* collateralRatio = _collateralRatio;
        liquidationRatio = _liquidationRatio; */
        oracle = IOracle(_oracle);
        usdToken = UsdToken(_usdToken);
    }

    function _manageCredit(int256 _amount) internal {
        if (_amount == 0) return;
        require(usdToken.totalSupply() > 0);
        if (_amount >= 0) {
            magnifiedCreditPerUsd = magnifiedCreditPerUsd.add(
              _amount.mul(magnitude) / _toInt256Safe(usdToken.totalSupply())
            );
        } else {
            magnifiedCreditPerUsd = magnifiedCreditPerUsd.sub(
              _amount.mul(magnitude) / _toInt256Safe(usdToken.totalSupply())
            );
        }
    }

    function depositEth() payable external {
        //Don't allow deposits on accounts with open bids
        require(bidStart[msg.sender] == 0);
        ethCollateral[msg.sender] += msg.value;
    }

    function depositUsd(uint256 _amount) external {
        //Don't allow deposits on accounts with open bids
        require(bidStart[msg.sender] == 0);
        //Will revert if transfer fails, or we try and pay back more than we've borrowed
        usdWithdrawn[msg.sender] = usdWithdrawn[msg.sender].sub(_amount);
        require(usdToken.burnFrom(msg.sender, _amount));
        _burn(msg.sender, _amount);
    }

    function withdrawEth(uint256 _amount) external {
        //Don't allow withdrawals on accounts with open bids
        require(bidStart[msg.sender] == 0);
        ethCollateral[msg.sender] = ethCollateral[msg.sender].sub(_amount);
        require(_checkLiquidity(msg.sender));
    }

    function withdrawUsd(uint256 _amount) external {
        //Don't allow withdrawals on accounts with open bids
        require(bidStart[msg.sender] == 0);
        usdWithdrawn[msg.sender] = usdWithdrawn[msg.sender].add(_amount);
        require(_checkLiquidity(msg.sender));
        require(usdToken.mint(msg.sender, _amount));
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
        require(bidStart[_account].add(auctionLength) >= now.add(auctionLength));
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
        require(bidStart[_account].add(auctionLength) < now.add(auctionLength));

        // Calculate liquidity difference
        int256 credit = _toInt256Safe(submittedBids[_account][msg.sender]).sub(_toInt256Safe(usdWithdrawn[_account]));
        msg.sender.transfer(ethCollateral[_account]);
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

    function _checkLiquidity(address _account) internal returns (bool) {
        //Check whether account is still liquid
        uint256 usdValueOfEth = ethCollateral[_account].mul(_getUsdPrice()).div(10**18);
        return usdValueOfEth.mul(liquidationRatio).div(10**18) >= usdWithdrawn[_account];
    }

    function _availableCredit(address _account) internal returns (uint256) {
        //Throws if credit < 0;
        uint256 usdValueOfEth = ethCollateral[_account].mul(_getUsdPrice()).div(10**18);
        return usdValueOfEth.mul(liquidationRatio).div(10**18).sub(usdWithdrawn[_account]);
    }

    function _getUsdPrice() internal returns (uint256) {
        return oracle.getPrice();
    }

    function _mint(address _account, uint256 _amount) internal {
        magnifiedCreditCorrections[_account] = magnifiedCreditCorrections[_account]
          .sub(magnifiedCreditPerUsd.mul(_toInt256Safe(_amount)));
    }

    function _burn(address _account, uint256 _amount) internal {
        magnifiedCreditCorrections[_account] = magnifiedCreditCorrections[_account]
          .add(magnifiedCreditPerUsd.mul(_toInt256Safe(_amount)));
    }

    function _toInt256Safe(uint256 a) internal pure returns (int256) {
        int256 b = int256(a);
        require(b >= 0);
        return b;
    }
}
