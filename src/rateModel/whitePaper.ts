/**
 * 直线型利率模型
 * WhitePaperInterestRateModel
 */

import { formatUnits, parseEther, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { createContracts } from "../contracts";
import { color } from "../infomaction";

/**
 * 部署erc20
 */
export const main = async () => {
    const { cUSDT, usdt, signer, comptroller} = await createContracts();
    const modelAddress = await cUSDT.interestRateModel();
    const white:any = await ethers.getContractAt("WhitePaperInterestRateModel", modelAddress, signer).catch(err => console.log(err));

    color.magenta(`年化基准利率 ${await white.baseRatePerBlock()}`)
    color.magenta(`年化基准成率 ${await white.multiplierPerBlock()}`)

    await usdt.approve(cUSDT.address,ethers.constants.MaxUint256);
    await cUSDT.mint(parseUnits("100"),{ gasLimit: 3000000 })

    color.magenta(`borrow - 账户借款余额（含利息): ${formatUnits(await cUSDT.borrowBalanceStored(signer.address))}`);
    color.magenta(`borrow - 账户的存款额度(cToken)": ${formatUnits(await cUSDT.balanceOf(signer.address))}`);
    color.magenta(`borrow - 账户供应额度(标的资产)": ${formatUnits((await (await cUSDT.balanceOfUnderlying(signer.address)).wait()).events[1].args[0])}`);
    await cUSDT.borrow(parseUnits("70"));
    color.magenta(`年化基准利率 ${await white.baseRatePerBlock()}`)
    color.magenta(`年化基准成率 ${await white.multiplierPerBlock()}`)
    console.log("每个区块存款利率", formatUnits(await cUSDT.supplyRatePerBlock()))
    console.log(formatUnits(await cUSDT.borrowIndex()))
    // console.log(formatUnits(await cUSDT.initialExchangeRateMantissa()))
    console.log(formatUnits(await cUSDT.reserveFactorMantissa()))
    // console.log(await cUSDT.multiplierPerBlock())
    // console.log(await cUSDT.baseRatePerBlock())

}


main();