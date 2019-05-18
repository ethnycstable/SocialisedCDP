pragma solidity ^0.5.0;

import "./IOracle.sol";
import "./IMedianizer.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract MakerDaoOracle is IOracle, Ownable {
    address public medianizer;

    /**
      * @notice Creates a new Maker based oracle
      * @param _medianizer Address of Maker medianizer
      */
    constructor(address _medianizer) public {
        medianizer = _medianizer;
    }

    /**
    * @notice Returns price - should throw if not valid
    */
    function getPrice() external returns(uint256) {
        (bytes32 price, bool valid) = IMedianizer(medianizer).peek();
        require(valid, "MakerDAO Oracle returning invalid value");
        return uint256(price);
    }

}
