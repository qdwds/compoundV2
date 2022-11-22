import { createContracts } from "../contracts";
import { formatUnits, parseEther, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { marketInfo, blockInfo, userInfo, color } from "./infomaction";


// 存款
const mint = async () => {
    const { cErc20Delegator, erc20Token, signer } = await createContracts();
    await erc20Token.approve(cErc20Delegator.address, ethers.constants.MaxUint256)
    await cErc20Delegator.mint(parseUnits("1000"));
    color.magenta(`mint - 账户的存款额度(标的资产)": ${formatUnits(await cErc20Delegator.balanceOf(signer.address))}`);
    color.magenta(`mint - 账户供应额度(cToken)": ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[0].args[0])}`);
}


// 取款 输入cToken兑换标的资产数量
const redeem = async() => {
    const { cErc20Delegator, signer } = await createContracts();
    const amountAll = await cErc20Delegator.redeem(parseUnits("88"));
    const tx = await amountAll.wait();
    color.magenta('tx')
    color.magenta(`redeem - 账户的存款额度(标的资产): ${formatUnits(await cErc20Delegator.balanceOf(signer.address))}`);
    color.magenta(`redeem - 账户供应额度(cToken): ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[0].args[0])}`);
}


// 取款 输入标的资产数量算出cTokenr然后提取
const redeemUnderlying = async () =>{
    const { cErc20Delegator, signer } = await createContracts();
    const amount = await cErc20Delegator.redeemUnderlying(parseUnits("22"));
    await amount.wait();
    color.magenta(`redeemUnderlying - 账户的存款额度(标的资产): ${formatUnits(await cErc20Delegator.balanceOf(signer.address))}`);
    color.magenta(`redeemUnderlying - 账户供应额度(cToken): ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[0].args[0])}`);
}

// 借款
const borrow = async() =>{
    const { cErc20Delegator, signer } = await createContracts();
    const transaction = await cErc20Delegator.borrow(parseEther("50"));
    const tx = await transaction.wait();
    color.magenta(`borrow - 账户借款余额（含利息: ${formatUnits(await cErc20Delegator.borrowBalanceStored(signer.address))}`);
}
// 还款
const repayBorrow = async() =>{
    const { cErc20Delegator, signer } = await createContracts();
    const transaction = await cErc20Delegator.repayBorrow(parseEther("25"));
    await transaction.wait();
    color.magenta(`repayBorrow - 账户借款余额（含利息: ${formatUnits(await cErc20Delegator.borrowBalanceStored(signer.address))}`);
}

// 代还款
const repayBorrowBehalf = async () => {
    const { cErc20Delegator, signer, account, erc20Token, accountCToken,accountERC20 } = await createContracts();
    await erc20Token.transfer(account.address, parseUnits("1000"));
    color.magenta(`repayBorrowBehalf account balanceOf): ${formatUnits(await erc20Token.balanceOf(account.address))}`);
    color.yellow(`repayBorrowBehalf signer balanceOf): ${formatUnits(await erc20Token.balanceOf(signer.address))}`);
    color.yellow(`cErc20Delegator signer - 账户的存款额度(标的资产): ${formatUnits(await cErc20Delegator.balanceOf(signer.address))}`);
    color.yellow(`cErc20Delegator signer - 账户供应额度(cToken): ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[0].args[0])}`);
    await accountERC20.approve(accountCToken.address, ethers.constants.MaxUint256)
    await accountCToken.mint(parseUnits("1000"));
    await accountCToken.borrow(parseEther("1000"));
    color.magenta(`repayBorrowBehalf account - 账户借款余额（含利息) ${formatUnits(await accountCToken.borrowBalanceStored(account.address))}`);
    await cErc20Delegator.repayBorrowBehalf(account.address, parseUnits("999"));
    color.yellow(`cErc20Delegator signer - 账户的存款额度(标的资产): ${formatUnits(await cErc20Delegator.balanceOf(signer.address))}`);
    color.yellow(`cErc20Delegator signer - 账户供应额度(cToken): ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[0].args[0])}`);
    color.yellow(`repayBorrowBehalf signer balanceOf): ${formatUnits(await erc20Token.balanceOf(signer.address))}`);
    color.magenta(`repayBorrowBehalf account - 账户借款余额（含利息) ${formatUnits(await accountCToken.borrowBalanceStored(account.address))}`);
    
}


// 清算
const liquidateBorrow = async() =>{
    
}
;(async ()=>{
    // await userInfo();
    // await mint();
    // await borrow()
    // await repayBorrow()
    // await redeem()
    // await redeemUnderlying();
    await repayBorrowBehalf()
    // await marketInfo()
    // await userInfo();
    // await blockInfo();
})()
