/**
 * 拐点型利率模型
 */


import { Contract } from "ethers";
import { formatUnits, parseEther, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { createContracts } from "../contracts";
import { color } from "../infomaction";
import { getCTokenInfo, getRateModelInfo } from "../model";



export const main = async () => {
    const { cDAI, dai, signer } = await createContracts();
    const modelAddress = await cDAI.interestRateModel();
    const white: any = await ethers.getContractAt("WhitePaperInterestRateModel", modelAddress, signer).catch(err => console.log(err));

    await getRateModelInfo(white, cDAI);

    await dai.approve(cDAI.address, ethers.constants.MaxUint256);
    await cDAI.mint(parseUnits("1000"), { gasLimit: 3000000 })
    await cDAI.borrow(parseUnits("100"));
    color.green(`borrow - 账户借款余额（含利息): ${formatUnits(await cDAI.borrowBalanceStored(signer.address))}`);
    color.magenta(`borrow - 账户借款余额（含利息): ${formatUnits(await cDAI.borrowBalanceStored(signer.address))}`);
    color.magenta(`borrow - 账户的存款额度(cToken)": ${formatUnits(await cDAI.balanceOf(signer.address))}`);
    color.magenta(`borrow - 账户供应额度(标的资产)": ${formatUnits((await (await cDAI.balanceOfUnderlying(signer.address)).wait()).events[1].args[0])}`);
    await getRateModelInfo(white, cDAI);

    await cDAI.borrow(parseUnits("500"));
    color.green(`borrow - 账户借款余额（含利息): ${formatUnits(await cDAI.borrowBalanceStored(signer.address))}`);
    await getRateModelInfo(white, cDAI);

    await cDAI.borrow(parseUnits("250"));
    color.green(`borrow - 账户借款余额（含利息): ${formatUnits(await cDAI.borrowBalanceStored(signer.address))}`);
    await getRateModelInfo(white, cDAI);

    await cDAI.borrow(parseUnits("49"));
    color.green(`borrow - 账户借款余额（含利息): ${formatUnits(await cDAI.borrowBalanceStored(signer.address))}`);
    await getRateModelInfo(white, cDAI);
}



main();