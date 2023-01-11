import { createContracts } from "../contracts";
import { formatUnits, parseEther, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { color } from "./infomaction";

const repayBorrowBehalf = async () => {
    // account欠款  signer还款
    // 模拟account借钱
    const { cErc20Delegator, signer, account, erc20Token, accountCToken, accountERC20 } = await createContracts();
    await erc20Token.transfer(account.address, parseUnits("100"));
    await accountERC20.approve(accountCToken.address, ethers.constants.MaxUint256,{gasLimit:5000000})
    await accountCToken.mint(parseUnits("100"));
    await accountCToken.borrow(parseUnits("100"));  //  借钱借入的肯定是标的资产
    color.magenta(`cErc20Delegator account - 账户供应额度(cToken): ${formatUnits(await accountCToken.balanceOf(account.address))}`);
    color.magenta(`accountCToken account - 账户的存款额度(标的资产): ${formatUnits((await (await accountCToken.balanceOfUnderlying(account.address)).wait()).events[1].args[0])}`);
    // await accountCToken.redeem(parseUnits("100"))
    // color.magenta(`accountCToken account - 账户供应额度(cToken): ${formatUnits(await accountCToken.balanceOf(account.address))}`);
    // color.magenta(`accountCToken account - 账户的存款额度(标的资产): ${formatUnits((await (await accountCToken.balanceOfUnderlying(account.address)).wait()).events[1].args[0])}`);
    const result = formatUnits(await accountCToken.borrowBalanceStored(account.address))
    color.magenta(`account - 借款额度 ${result}`)
    // signer 还钱。代还款支持全部还完
    cErc20Delegator.repayBorrowBehalf(account.address,parseUnits(result));
    color.magenta(`account - 借款额度 ${formatUnits(await accountCToken.borrowBalanceStored(account.address))}`)
}


repayBorrowBehalf()
    .catch(err => console.log(err))