import { createContracts } from "../contracts";
import { formatUnits, parseEther, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { marketInfo, blockInfo, userInfo, color } from "../infomaction";
import { BigNumber } from "ethers";
/**
 * account借钱，signer清算
 */
const balanceOfUnderlying = async (address:string) => {
    const { accountCToken } = await createContracts();
    return `${(await (await accountCToken.balanceOfUnderlying(address)).wait()).events[1].args[0]}`
}
// 清算
/**
 * account 借钱
 * signer 清算
 */
const liquidateBorrow = async () => {
    const { cErc20Delegator, erc20Token, oracle, cEther, account, signer, accountCToken, accountERC20, comptroller } = await createContracts();
    //  还原价格
    await oracle.setUnderlyingPrice(cErc20Delegator.address, parseUnits("1"));
    console.log("当前资产价格 ",formatUnits(await oracle.getUnderlyingPrice(cErc20Delegator.address)));
    // account 存钱 借钱
    await erc20Token.transfer(account.address, parseUnits("100"));
    await accountERC20.approve(accountCToken.address, ethers.constants.MaxUint256);
    await accountCToken.mint(parseUnits("100"));

    // account 获取标的资产额度
    const b = await balanceOfUnderlying(account.address);

    // color.magenta(`account - erc20: ${formatUnits(await erc20Token.balanceOf(account.address))}`);
    // color.magenta(`account - 账户的存款额度(cToken)": ${formatUnits(await accountCToken.balanceOf(account.address))}`);
    // color.magenta(`account - 账户供应额度(标的资产)": ${formatUnits(b)}`);

    // account 借钱 75%
    await accountCToken.borrow(BigNumber.from(b).mul(750).div(1000));

    //  account 借款额度
    const accountBorrow = await accountCToken.borrowBalanceStored(account.address);

    color.magenta(`account - 账户的存款额度(cToken)": ${formatUnits(await accountCToken.balanceOf(account.address))}`);
    color.magenta(`account - 账户供应额度(标的资产)": ${formatUnits(b)}`);
    color.magenta(`account - 账户借款余额（含利息): ${formatUnits(accountBorrow)}`);

    //  模拟价格下跌 50 % ，触发清算机制
    await(await oracle.setUnderlyingPrice(cErc20Delegator.address, parseUnits("0.5"))).wait();

    // mint cToken 用作抵押资产
    await erc20Token.approve(cErc20Delegator.address, ethers.constants.MaxUint256);
    await(await cErc20Delegator.mint(parseUnits("1000"))).wait();
    color.yellow(`signer - erc20: ${formatUnits(await erc20Token.balanceOf(signer.address))}`);
    color.yellow(`signer - 账户的存款额度(cToken)": ${formatUnits(await cErc20Delegator.balanceOf(signer.address))} `);
    color.yellow(`signer - 账户供应额度(标的资产)": ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[1].args[0])}`);


    // signer 清算 account 借款的 50%；
    // 获取预计清算额度
    const liquidateBorrow = accountBorrow * 0.5
    color.green(`开始清算程序 - 预计可以清算 ${formatUnits(String(liquidateBorrow))}` );
    //  开始清算
    await cErc20Delegator.liquidateBorrow(account.address, String(liquidateBorrow), cErc20Delegator.address, { gasLimit: 30000000 });

    color.magenta(`account - erc20: ${formatUnits(await erc20Token.balanceOf(account.address))}`);
    color.magenta(`account - 账户的存款额度(cToken)": ${formatUnits(await accountCToken.balanceOf(account.address))}`);
    color.magenta(`account - 账户供应额度(标的资产)": ${formatUnits((await (await accountCToken.balanceOfUnderlying(account.address)).wait()).events[1].args[0])}`);
    color.yellow(`signer - erc20: ${formatUnits(await erc20Token.balanceOf(signer.address))}`);
    color.yellow(`signer - 账户的存款额度(cToken)": ${formatUnits(await cErc20Delegator.balanceOf(signer.address))} `);
    color.yellow(`signer - 账户供应额度(标的资产)": ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[1].args[0])}`);
    // color.magenta(`account - 账户的存款额度(cToken)": ${formatUnits(await accountCToken.balanceOf(signer.address))}`);
}


liquidateBorrow()
    .catch(err => console.log(err))