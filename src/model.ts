import { BigNumber, Contract } from "ethers";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { createContracts } from "./contracts";
import { color } from "./infomaction";

// 年华区块数
const blocksPerYear = BigNumber.from("2102400");
export const getCTokenInfo = async (address: string) => {
    const { signer } = await createContracts();
    const cToken = await ethers.getContractAt("CErc20Delegator", address, signer);
    const cash = await cToken.getCash();
    const borrows = await cToken.totalBorrows();
    const reserves = await cToken.totalReserves();
    return {
        cash,
        borrows,
        reserves
    }
}

export const getRateModelInfo =async (model:Contract,cToken:Contract) => {
    const { cUSDT } = await createContracts();
    const { cash, borrows, reserves, } = await getCTokenInfo(cToken.address);
    const reserveFactorMantissa = await cToken.reserveFactorMantissa();
    // 存款利率
    const supple = (await model.getSupplyRate(cash, borrows, reserves,reserveFactorMantissa)).mul(blocksPerYear);
    //  借款利率
    const borrow = (await model.getBorrowRate(cash, borrows, reserves)).mul(blocksPerYear)
    // 使用率
    const utilization = await model.utilizationRate(cash, borrows, reserves);
    //  年化利率
    const baseRatePerBlockYear = (await model.baseRatePerBlock()).mul(blocksPerYear);
    // 年化乘基
    const multiplierPerBlock = (await model.multiplierPerBlock()).mul(blocksPerYear);
    //  兑换率
    const exchangeRate = await cUSDT.exchangeRateStored();
    
    color.magenta(`存款利率 ${formatUnits(supple.mul("100"))}%`);
    color.magenta(`借款利率 ${formatUnits(borrow.mul("100"))}%`);
    color.magenta(`使用率   ${formatUnits(utilization.mul("100"))}%`);
    color.magenta(`年化利率 ${formatUnits(baseRatePerBlockYear.mul("100"))}%`);
    color.magenta(`年化乘基 ${formatUnits(multiplierPerBlock)}`);
    color.magenta(`兑换率   ${formatUnits(exchangeRate)}`);
}