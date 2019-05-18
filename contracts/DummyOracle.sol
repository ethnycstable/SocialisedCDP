pragma solidity ^0.5.2;

import "./IOracle.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract DummyOracle is IOracle, Ownable {
    uint256 public manualPrice;
    event SetManualPrice(uint256 _oldPrice, uint256 _newPrice);

    /**
    * @notice Returns price - should throw if not valid
    */
    function getPrice() external view returns(uint256) {
        return manualPrice;
    }

    /**
      * @notice Set a manual price.
      * @param _price Price to set
      */
    function setPrice(uint256 _price) public onlyOwner {
        emit SetManualPrice(manualPrice, _price);
        manualPrice = _price;
    }

}
