pragma solidity ^0.5.2;

interface IOracle {

    /**
    * @notice Returns price - should throw if not valid
    */
    function getPrice() external view returns(uint256);

}
