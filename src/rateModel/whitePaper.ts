/**
 * 直线型利率模型
 * WhitePaperInterestRateModel
 */

import { Contract } from "ethers";
import { formatUnits, parseEther, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { createContracts } from "../contracts";
import { color } from "../infomaction";
import { getRateModelInfo } from "../model";



export const main = async () => {
    const { cUSDT, usdt, signer } = await createContracts();
    const modelAddress = await cUSDT.interestRateModel();
    const white: any = await ethers.getContractAt("WhitePaperInterestRateModel", modelAddress, signer).catch(err => console.log(err));
    
    await getRateModelInfo(white, cUSDT);
    await usdt.approve(cUSDT.address, ethers.constants.MaxUint256);
    await cUSDT.mint(parseUnits("1000"), { gasLimit: 3000000 })
    await cUSDT.borrow(parseUnits("100"));
    color.green(`borrow - 账户借款余额（含利息): ${formatUnits(await cUSDT.borrowBalanceStored(signer.address))}`);
    color.magenta(`borrow - 账户借款余额（含利息): ${formatUnits(await cUSDT.borrowBalanceStored(signer.address))}`);
    color.magenta(`borrow - 账户的存款额度(cToken)": ${formatUnits(await cUSDT.balanceOf(signer.address))}`);
    color.magenta(`borrow - 账户供应额度(标的资产)": ${formatUnits((await (await cUSDT.balanceOfUnderlying(signer.address)).wait()).events[1].args[0])}`);
    await getRateModelInfo(white, cUSDT);

    await cUSDT.borrow(parseUnits("500"));
    color.green(`borrow - 账户借款余额（含利息): ${formatUnits(await cUSDT.borrowBalanceStored(signer.address))}`);
    await getRateModelInfo(white, cUSDT);

    await cUSDT.borrow(parseUnits("250"));
    color.green(`borrow - 账户借款余额（含利息): ${formatUnits(await cUSDT.borrowBalanceStored(signer.address))}`);
    await getRateModelInfo(white, cUSDT);
}


main();