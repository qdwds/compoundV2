// compound 用户存款存款

// 用户先compound存入USDT, compound会根据当前的汇率算出铸造cUSDT的数量，将对应的cUSDT代币转移到用户账户中
import { createContracts } from "./contracts";
import address from "../abi/address.json";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { Contract } from "ethers";
import { comptrollerG7_enterMarkets, comptrollerG7__supportMarket } from "./comptroller";
import { ethers } from "hardhat";


/**
 * 把对应的token存入合约中，兑换处指定数量的cToken
 */
const mint = async () => {
    const { cErc20Delegator, erc20Token } = await createContracts();
    await erc20Token.approve(cErc20Delegator.address, ethers.constants.MaxUint256)
    const tx = await cErc20Delegator.mint(parseUnits("1000"));
    console.log(tx)
}

export const cErc20Store =async () => {
    const { cErc20Delegator, compoundG7,signer,erc20Token } = await createContracts();
    const interestRateModel = await cErc20Delegator.interestRateModel();
    console.log("利率模型合约 ",formatUnits(interestRateModel));
    const reserveFactorMantissa = await cErc20Delegator.reserveFactorMantissa();
    console.log("储备金利率", formatUnits(reserveFactorMantissa));
    const accrualBlockNumber = await cErc20Delegator.accrualBlockNumber();
    console.log("上一次计算过利息的区块", formatUnits(accrualBlockNumber));
    const borrowIndex = await cErc20Delegator.borrowIndex();
    console.log("指标", formatUnits((borrowIndex)))
    console.log("市场总储备金", formatUnits(await cErc20Delegator.totalReserves()))
    console.log("流通中的代币总数", formatUnits(await cErc20Delegator.totalSupply()))
    console.log("当前账户的存款余额", formatUnits(await cErc20Delegator.balanceOf(signer.address)))
    console.log("当前账户的供应存款余额", (await cErc20Delegator.balanceOfUnderlying(signer.address)))
    console.log("该合约拥有的标的资产数量", (await cErc20Delegator.getCash()))
    console.log("当前存在的市场",await compoundG7.getAllMarkets())




    console.log(formatUnits(await cErc20Delegator.totalSupply()));
    console.log(formatUnits(await erc20Token.totalSupply()));
}




const main = async () => {
    const { cErc20Delegator, erc20Token, compoundG7 } = await createContracts();
    console.log("当前存在的市场",await compoundG7.getAllMarkets())
    // 加入市场
    // await comptrollerG7__supportMarket(cErc20Delegator.address);

    //  类似交易对？？  token <=> cToken
    await comptrollerG7_enterMarkets([ cErc20Delegator.address])
    
    await mint();

    await cErc20Store();
}
main();
