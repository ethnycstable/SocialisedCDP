var Cdp = artifacts.require("./Cdp.sol");
var DummyOracle = artifacts.require("./DummyOracle.sol");
var MakerDaoOracle = artifacts.require("./MakerDaoOracle.sol");
var UsdToken = artifacts.require("./UsdToken.sol");

module.exports = async function(deployer) {
    await deployer.deploy(UsdToken);
    await deployer.deploy(DummyOracle);
    await deployer.deploy(Cdp, DummyOracle.address, UsdToken.address);
    let usdToken = await UsdToken.deployed();
    await usdToken.setCdp(Cdp.address);
};
