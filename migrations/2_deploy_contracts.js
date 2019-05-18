var SocialisedCdp = artifacts.require("./SocialisedCdp.sol");
var DummyOracle = artifacts.require("./DummyOracle.sol");
var MakerDaoOracle = artifacts.require("./MakerDaoOracle.sol");
var UsdToken = artifacts.require("./UsdToken.sol");

module.exports = async function(deployer) {
    await deployer.deploy(UsdToken);
    await deployer.deploy(DummyOracle);
    await deployer.deploy(SocialisedCdp, DummyOracle.address, UsdToken.address);
    let usdToken = await UsdToken.deployed();
    await usdToken.setCdp(SocialisedCdp.address);
};
