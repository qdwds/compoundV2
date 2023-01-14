import { CallTracker } from "assert";
import { formatUnits } from "ethers/lib/utils";
import { createContracts } from "./contracts";

// 当前用户数据
export const userInfo = async () => {
    const { cErc20Delegator, signer } = await createContracts();
    color.green(`all - 账户借款余额（含利息: ${formatUnits(await cErc20Delegator.borrowBalanceStored(signer.address))}`);
    color.green(`all - 账户的存款额度(标的资产): ${formatUnits(await cErc20Delegator.balanceOf(signer.address))}`);
    color.green(`all - 账户供应额度(cToken): ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[0].args[0])}`);
}

// 其他
export const blockInfo = async () => {
    const { cErc20Delegator } = await createContracts();
    // color.yellow(`"利率模型合约 ": ${formatUnits(await cErc20Delegator.interestRateModel())}`);
    color.green(`all - 上一次计算过利息的区块: ${formatUnits(await cErc20Delegator.accrualBlockNumber())}`);
    color.green(`all - 每个区块的借款汇率: ${formatUnits(await cErc20Delegator.borrowRatePerBlock())}`);
    color.green(`all - 每个区块的供应利率: ${formatUnits(await cErc20Delegator.supplyRatePerBlock())}`);
}

// 市场相关数据
export const marketInfo = async () => {
    const { cErc20Delegator } = await createContracts();
    color.green(`all - 市场储备金利率: ${formatUnits(await cErc20Delegator.reserveFactorMantissa())}`);
    color.green(`all - 市场总储备金(标的资产)": ${formatUnits(await cErc20Delegator.totalReserves())}`);
    color.green(`all - 市场目前可用的现金总额": ${formatUnits(await cErc20Delegator.getCash())}`);
    color.green(`all - 市场总供应量": ${formatUnits(await cErc20Delegator.totalSupply())}`);;
    color.green(`all - 市场总汇率": ${formatUnits(await cErc20Delegator.exchangeRateStored())}`);
    color.green(`all - 市场借款总额度（含利息）": ${formatUnits(await cErc20Delegator.totalBorrows())}`);
    color.green(`all - 市场借款利率": ${formatUnits(await cErc20Delegator.borrowRatePerBlock())}`);
    color.green(`all - 市场每个区块供应率": ${formatUnits(await cErc20Delegator.supplyRatePerBlock())}`);
    color.green(`all - 市场指标(使用率)": ${formatUnits(await cErc20Delegator.borrowIndex())}`);

}


class Color{
    green(v:any){
        console.log('\x1B[32m%s\x1B[0m',v);
    }
    red(v:any){
        console.log('\x1B[31m%s\x1B[0m',v);
    }
    yellow(v:any){
        console.log('\x1B[33m%s\x1B[0m',v);
    }
    magenta(v:any){
        console.log('\x1B[35m%s\x1B[39m',v);
    }
}
export const color = new Color();