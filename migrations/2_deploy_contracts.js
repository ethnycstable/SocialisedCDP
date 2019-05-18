var SocialisedCdp = artifacts.require("./SocialisedCdp.sol");
var DummyOracle = artifacts.require("./DummyOracle.sol");
// var MakerDaoOracle = artifacts.require("./MakerDaoOracle.sol");
var UsdToken = artifacts.require("./UsdToken.sol");
var BigNumber = require('bignumber.js');


module.exports = async function(deployer, network, accounts) {
    await deployer.deploy(UsdToken);
    await deployer.deploy(DummyOracle);
    await deployer.deploy(SocialisedCdp, DummyOracle.address, UsdToken.address);
    let usdToken = await UsdToken.deployed();
    let oracle = await DummyOracle.deployed();
    let cdp = await SocialisedCdp.deployed();
    console.log("Setup");
    await usdToken.setCdp(SocialisedCdp.address);
    await oracle.setPrice(new BigNumber(200*10**18));
    console.log("CDP 1");
    await cdp.depositEth({value: new BigNumber(2*10**18)});
    await cdp.withdrawUsd(new BigNumber(360*10**18));
    console.log("CDP 2");
    await cdp.depositEth({value: new BigNumber(2*10**18), from: accounts[1]});
    await cdp.withdrawUsd(new BigNumber(10*10**18), {from: accounts[1]});
    console.log("Setup 2");
    await oracle.setPrice(new BigNumber(100*10**18));
    await usdToken.approve(SocialisedCdp.address, new BigNumber(10*10**18), {from: accounts[1]});
    console.log("Bid");
    let allowance = await usdToken.allowance(accounts[1], SocialisedCdp.address);
    console.log(allowance.toString());
    await cdp.bidMarginCall(accounts[0], new BigNumber(10*10**18), {from: accounts[1]});
};
