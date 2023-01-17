import { parseEther } from "ethers/lib/utils";
import { writeFileSync } from "fs";
import { ethers } from "hardhat";
import { join, resolve } from "path";
import { cEtherDeploy, cEther__setReserveFactor, cEther__supportMarket } from "./CEther.module";
import { compTokenDeploy, setCompAddress } from "./comp.module";
import { unitollerDeploy, comptrollerDeploy, unitoller__setPendingImplementation, ccomptroller__setLiquidationIncentive, comptroller__become, comptroller__setCloseFactor, comptroller__setPriceOracle, comptroller__setCollateralFactor, comptroller_setCompAddress } from "./comptroller.module";
import { erc20TokenDeploy, CErc20DelegateDeploy, cErc20DelegatorDeploy, cToken__setReserveFactor, cErc20Delegator_supportMarket } from "./cToken.module";
import { jumpRateModelV2Deploy, WhitePaperInterestRateModelDeploy } from "./interestRate.module";
import { simplePriceOracleDeploy, simplePriceOracle_setUnderlyingPrice } from "./priceOracle.module";
import { DAITokenDeploy, USDTTokenDeploy } from "./tokens.module";

async function main() {
  const signer = await ethers.provider.getSigner();
  const owner = await signer.getAddress();

  // Comp token 合约
  const comp = await compTokenDeploy();
  //  set comp token address 
  // await setCompAddress(comp.address);
  // 代理合约
  const unitoller = await unitollerDeploy();
  //  控制合约
  const comptroller = await comptrollerDeploy();
  // 设置奖励comp token地址
  await comptroller_setCompAddress(comptroller.address, comp.address);
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
  //  清算比例
  await comptroller__setCloseFactor(comptroller.address);
  // 设置清算激励，额度来之被清算人
  await ccomptroller__setLiquidationIncentive(comptroller.address);
  // 设置预言机
  await comptroller__setPriceOracle(comptroller.address, simplePriceOracle.address)

  // 利率模型
  // 拐点型利率模型
  const jumpRateModelV2 = await jumpRateModelV2Deploy(owner);
  // 直线型利率模型
  const whitePaperInterestRateModel = await WhitePaperInterestRateModelDeploy(owner);


  // usdt => cUsdt
  const erc20Token = await erc20TokenDeploy();  //  不在compound合约中
  // const weth9 = await weth9Deploy();
  const cErc20Delegate = await CErc20DelegateDeploy();
  // erc20Token 真实token 兑换 cerc20Token

  // 该方法就是 用token 还ctoken， 只能是传入的token兑换，其他token无法兑换
  // 等于部署cUSDT
  const cErc20Delegator = await cErc20DelegatorDeploy(
    erc20Token.address, 
    comptroller.address, 
    jumpRateModelV2.address, 
    owner, 
    cErc20Delegate.address,
    "COMP USD",
    "cUSDT"
  )
  const cEther = await cEtherDeploy(
    comptroller.address, 
    jumpRateModelV2.address, 
    owner
  );

  // 加入市场
  await cErc20Delegator_supportMarket(
    comptroller.address, 
    cErc20Delegator.address
  );
  await cEther__supportMarket(
    comptroller.address, 
    cEther.address
  );

  // 设置市场价格 市场价格 根据  1 * 10 ** 18 == 1USDT 计算
  // cToken 价格
  await simplePriceOracle_setUnderlyingPrice(
    signer,
    simplePriceOracle.address, 
    cErc20Delegator.address, 
    parseEther("1")
  );
  // cEther 价格
  await simplePriceOracle_setUnderlyingPrice(
    signer,
    simplePriceOracle.address, 
    cEther.address, 
    parseEther("2000")
  );

  // 设置储备金系数
  await cToken__setReserveFactor(cErc20Delegator.address);
  await cEther__setReserveFactor(cEther.address);

  
  // 设置抵押率
  await comptroller__setCollateralFactor(
    comptroller.address, 
    cErc20Delegator.address
  );


  // 利率模型使用的token
  // 直线型
  const usdt = await USDTTokenDeploy();
  const cUSDT = await cErc20DelegatorDeploy(usdt.address, comptroller.address, whitePaperInterestRateModel.address, owner, cErc20Delegate.address,"COMP USDT","cUSDT")
  await cErc20Delegator_supportMarket(comptroller.address, cUSDT.address);
  await simplePriceOracle_setUnderlyingPrice(signer,simplePriceOracle.address, cUSDT.address, parseEther("1"));
  await cToken__setReserveFactor(cUSDT.address);
  await comptroller__setCollateralFactor(comptroller.address, cUSDT.address,"0.9")
  
  //  拐点型
  const dai = await DAITokenDeploy();
  const cDAI = await cErc20DelegatorDeploy(dai.address, comptroller.address, jumpRateModelV2.address, owner, cErc20Delegate.address,"COMP DAI","cDAI")
  await cErc20Delegator_supportMarket(comptroller.address, cDAI.address);
  await simplePriceOracle_setUnderlyingPrice(signer,simplePriceOracle.address, cDAI.address, parseEther("1"));
  await cToken__setReserveFactor(cDAI.address);
  await comptroller__setCollateralFactor(comptroller.address, cDAI.address,"0.9");

  const info = {
    comp: comp.address,
    unitoller: unitoller.address,
    comptroller: comptroller.address,
    simplePriceOracle: simplePriceOracle.address,
    whitePaperInterestRateModel:whitePaperInterestRateModel.address,
    jumpRateModelV2: jumpRateModelV2.address,
    erc20Token: erc20Token.address,
    cErc20Delegate: cErc20Delegate.address,
    cErc20Delegator: cErc20Delegator.address,
    cEther: cEther.address,
    usdt:usdt.address,
    cUSDT: cUSDT.address,
    dai:dai.address,
    cDAI: cDAI.address,
  }

  const infoPath = resolve(join(__dirname, "../abi/address.json"));
  await writeFileSync(infoPath, JSON.stringify(info));
  console.log(info);

}


main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
