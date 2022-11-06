import { writeFileSync } from "fs";
import { ethers } from "hardhat";
import { join, resolve } from "path";
import { cEtherDeploy, cEther__setReserveFactor, cEther__supportMarket } from "./CEther.module";
import { compTokenDeploy, setCompAddress } from "./comp.module";
import { unitollerDeploy, comptrollerG7Deploy, unitoller__setPendingImplementation, ccomptrollerG7__setLiquidationIncentive, comptrollerG7__become, comptrollerG7__setCloseFactor, comptrollerG7__setPriceOracle, comptrollerG7__setCollateralFactor } from "./comptroller.module";
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
  const comptrollerG7 = await comptrollerG7Deploy();
  // 预言机
  const simplePriceOracle = await simplePriceOracleDeploy();

  /**
   * 设置完成后对外提供 Comptroller 合约地址时，提供的是 Unitroller 合约地址。
   * 因为Comptroller 交给 Unitroller 代理了，所以对外需要提供 Unitroller 。
   */
  // 设置管理员 代理绑定 转移所有权
  await unitoller__setPendingImplementation(unitoller.address, comptrollerG7.address);
  // 设置g7代理合约地址 新的 Comptroller 接受所有权
  await comptrollerG7__become(comptrollerG7.address, unitoller.address);
  await comptrollerG7__setCloseFactor(comptrollerG7.address);
  await ccomptrollerG7__setLiquidationIncentive(comptrollerG7.address);
  // 设置预言机
  await comptrollerG7__setPriceOracle(comptrollerG7.address, simplePriceOracle.address)

  // 拐点型利率模型 ctoken = toekn。 eth = eth
  const cTokenJumpRateModelV2 = await jumpRateModelV2Deploy(owner);
  const etherJumpRateModelV2 = await jumpRateModelV2Deploy(owner);


  const erc20Token = await erc20TokenDeploy();  //  不在compound合约中
  const cErc20Delegate = await CErc20DelegateDeploy();
  // erc20Token 真实token 兑换 cerc20Token
  // 该方法就是 用token 还ctoken， 只能是传入的token兑换，其他token无法兑换
  const cErc20Delegator = await cErc20DelegatorDeploy(erc20Token.address, unitoller.address, cTokenJumpRateModelV2.address, owner, cErc20Delegate.address)

  const cEther = await cEtherDeploy(unitoller.address, etherJumpRateModelV2.address, owner);

  // 设置市场价格 市场价格 根据  1 * 10 ** 18 == 1USDT 计算
  // cToken 价格
  // await simplePriceOracle_setUnderlyingPrice(simplePriceOracle.address, cErc20Delegator.address, parseEther("1"));
  // // await simplePriceOracle_setUnderlyingPrice(simplePriceOracle.address, erc20Token.address, parseEther("1"))
  // await simplePriceOracle_setUnderlyingPrice(simplePriceOracle.address, cEther.address, parseEther("2"));

  // 设置保证金系数
  await cToken__setReserveFactor(cErc20Delegator.address);
  await cEther__setReserveFactor(cEther.address);

  // 加入市场
  await cErc20Delegator_supportMarket(comptrollerG7.address, cErc20Delegator.address);
  await cEther__supportMarket(comptrollerG7.address, cEther.address);

  // 设置抵押率
  await comptrollerG7__setCollateralFactor(comptrollerG7.address, cErc20Delegator.address);




  // tokens
  const usdt = await USDTTokenDeploy();

  const info = {
    comp: comp.address,
    unitoller: unitoller.address,
    comptrollerG7: comptrollerG7.address,
    simplePriceOracle: simplePriceOracle.address,
    etherJumpRateModelV2: etherJumpRateModelV2.address,
    cTokenJumpRateModelV2: cTokenJumpRateModelV2.address,
    erc20Token: erc20Token.address,
    cErc20Delegate: cErc20Delegate.address,
    cErc20Delegator: cErc20Delegator.address,
    cEther: cEther.address,
    usdt: usdt.address

  }

  const infoPath = resolve(join(__dirname,"../abi/address.json"));
  await writeFileSync(infoPath, JSON.stringify(info));
  console.log(info);

}


main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
