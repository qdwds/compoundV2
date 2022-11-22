import { parseEther } from "ethers/lib/utils";
import { writeFileSync } from "fs";
import { ethers } from "hardhat";
import { join, resolve } from "path";
import { cEtherDeploy, cEther__setReserveFactor, cEther__supportMarket } from "./CEther.module";
import { compTokenDeploy, setCompAddress } from "./comp.module";
import { unitollerDeploy, comptrollerDeploy, unitoller__setPendingImplementation, ccomptroller__setLiquidationIncentive, comptroller__become, comptroller__setCloseFactor, comptroller__setPriceOracle, comptroller__setCollateralFactor } from "./comptroller.module";
import { erc20TokenDeploy, CErc20DelegateDeploy, cErc20DelegatorDeploy, cToken__setReserveFactor, cErc20Delegator_supportMarket } from "./cToken.module";
import { jumpRateModelV2Deploy } from "./interestRate.module";
import { simplePriceOracleDeploy, simplePriceOracle_setUnderlyingPrice } from "./priceOracle.module";
import { USDTTokenDeploy } from "./tokens.module";

async function main() {
  const signer = await ethers.provider.getSigner();
  const owner = await signer.getAddress();

  // Comp token 合约
  const comp = await compTokenDeploy();

  await setCompAddress(comp.address); //  set comp token address 
  // 代理合约
  const unitoller = await unitollerDeploy();
  //  控制合约
  const comptroller = await comptrollerDeploy();

  // 预言机
  const simplePriceOracle = await simplePriceOracleDeploy();

  /**
   * 设置完成后对外提供 Comptroller 合约地址时，提供的是 Unitroller 合约地址。
   * 因为Comptroller 交给 Unitroller 代理了，所以对外需要提供 Unitroller 。
   */
  // 设置管理员 代理绑定 转移所有权
  await unitoller__setPendingImplementation(unitoller.address, comptroller.address);
  // 设置g7代理合约地址 新的 Comptroller 接受所有权
  await comptroller__become(comptroller.address, unitoller.address);
  await comptroller__setCloseFactor(comptroller.address);
  await ccomptroller__setLiquidationIncentive(comptroller.address);
  // 设置预言机
  await comptroller__setPriceOracle(comptroller.address, simplePriceOracle.address)

  // 拐点型利率模型 ctoken = toekn。 eth = eth
  const cTokenJumpRateModelV2 = await jumpRateModelV2Deploy(owner);
  const etherJumpRateModelV2 = await jumpRateModelV2Deploy(owner);


  const erc20Token = await erc20TokenDeploy();  //  不在compound合约中
  const cErc20Delegate = await CErc20DelegateDeploy();
  // erc20Token 真实token 兑换 cerc20Token
  // 该方法就是 用token 还ctoken， 只能是传入的token兑换，其他token无法兑换
  const cErc20Delegator = await cErc20DelegatorDeploy(erc20Token.address, comptroller.address, cTokenJumpRateModelV2.address, owner, cErc20Delegate.address)
  // ⚠️： 这里使用 unitoller 还是comptroller??????
  const cEther = await cEtherDeploy(comptroller.address, etherJumpRateModelV2.address, owner);

  // 加入市场
  await cErc20Delegator_supportMarket(comptroller.address, cErc20Delegator.address);
  await cEther__supportMarket(comptroller.address, cEther.address);

  // 设置市场价格 市场价格 根据  1 * 10 ** 18 == 1USDT 计算
  // cToken 价格
  await simplePriceOracle_setUnderlyingPrice(simplePriceOracle.address, cErc20Delegator.address, parseEther("1"));
  // await simplePriceOracle_setUnderlyingPrice(simplePriceOracle.address, erc20Token.address, parseEther("1"))
  // eth 有自己的设置价格吗？为啥报错？
  await simplePriceOracle_setUnderlyingPrice(simplePriceOracle.address, cEther.address, parseEther("2000"));

  // 设置保证金系数
  await cToken__setReserveFactor(cErc20Delegator.address);
  await cEther__setReserveFactor(cEther.address);

  
  // 设置抵押率
  await comptroller__setCollateralFactor(comptroller.address, cErc20Delegator.address);


  // tokens
  const usdt = await USDTTokenDeploy();

  const info = {
    comp: comp.address,
    unitoller: unitoller.address,
    comptroller: comptroller.address,
    simplePriceOracle: simplePriceOracle.address,
    etherJumpRateModelV2: etherJumpRateModelV2.address,
    cTokenJumpRateModelV2: cTokenJumpRateModelV2.address,
    erc20Token: erc20Token.address,
    cErc20Delegate: cErc20Delegate.address,
    cErc20Delegator: cErc20Delegator.address,
    cEther: cEther.address,
    usdt: usdt.address

  }

  const infoPath = resolve(join(__dirname, "../abi/address.json"));
  await writeFileSync(infoPath, JSON.stringify(info));
  console.log(info);

}


main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
