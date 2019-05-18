pragma solidity ^0.5.2;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

contract UsdToken is ERC20 {

    //Only address which can mint / burn tokens
    address public cdp;

    modifier onlyCdp {
        require(msg.sender == cdp);
        _;
    }

    function setCdp(address _cdp) external {
        //Can only be called once with a non-zero address
        require(cdp == address(0));
        require(_cdp != address(0));
        cdp = _cdp;
    }

    function mint(address to, uint256 value) external onlyCdp returns (bool) {
        _mint(to, value);
        return true;
    }

    function burnFrom(address from, uint256 value) external onlyCdp returns (bool) {
        _burn(from, value);
    }

}
