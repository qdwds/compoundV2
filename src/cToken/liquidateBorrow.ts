import { createContracts } from "../contracts";
import { formatUnits, parseEther, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { marketInfo, blockInfo, userInfo, color } from "./infomaction";
/**
 * 触发清算流程
 * 存钱
 * 借钱
 * 修改价格 => 触发清算
 * 查询余额
 * 清算人清算 借款人
 * 查询余额
 */
// 清算
const liquidateBorrow = async () => {
    const { cErc20Delegator, erc20Token, oracle, cEther, account, signer,accountCToken,accountERC20, comptroller} = await createContracts();
    // console.log(await comptroller.closeFactorMantissa());
    // console.log(await comptroller.getAssetsIn(signer.address));
    // console.log(await comptroller.getAssetsIn(account.address));
    // return
    await oracle.setUnderlyingPrice(cErc20Delegator.address, parseUnits("1"));

    // 存钱 借钱
    // await erc20Token.transfer(account.address, parseUnits("100"));
    // await accountERC20.approve(accountCToken.address, ethers.constants.MaxUint256);
    // await accountCToken.mint(parseUnits("100"));
    // 标的资产
    const b = (await (await accountCToken.balanceOfUnderlying(account.address)).wait()).events[1].args[0];
    console.log(b);
    /**
     * 疑问？？？？
     * 添加了100 到池子中，然后借款75 提示流动性不足 只能借60 ？？？
     *  为什么
     * 还有三天 一定 搞定加油！！！！！！！！！！
     */
color.magenta(`
    account - erc20: ${formatUnits(await erc20Token.balanceOf(account.address))}
    account - 账户的存款额度(cToken)": ${formatUnits(await accountCToken.balanceOf(account.address))}
    account - 账户供应额度(标的资产)": ${formatUnits(b)}`);
    await accountCToken.borrow(parseEther("60")).catch(err => console.log(err))
    const accountBorrow = await accountCToken.borrowBalanceStored(account.address);
    console.log(formatUnits(accountBorrow));
    
color.magenta(`
    account - 账户借款余额（含利息): ${formatUnits(accountBorrow)}`);

    color.magenta(`
    account - erc20: ${formatUnits(await erc20Token.balanceOf(account.address))}
    account - 账户的存款额度(cToken)": ${formatUnits(await accountCToken.balanceOf(account.address))}
    account - 账户供应额度(标的资产)": ${formatUnits(b)}`);
return
    const liquidateBorrow = accountBorrow * 0.5
    console.log("预计可以清算", formatUnits(String(liquidateBorrow)));
    //  价格下跌 50 % ，导致触发清算机制
    await oracle.setUnderlyingPrice(cErc20Delegator.address, parseUnits("0.5"));
    // mint cToken 用作抵押资产
    await erc20Token.approve(cErc20Delegator.address, ethers.constants.MaxUint256);
    await cErc20Delegator.mint(parseUnits("1000"));
color.magenta(`
    signer - erc20: ${formatUnits(await erc20Token.balanceOf(signer.address))}
    signer - 账户的存款额度(cToken)": ${formatUnits(await cErc20Delegator.balanceOf(signer.address))} 
    signer - 账户供应额度(标的资产)": ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[1].args[0])}`);

    // signer 清算 account 借款的 50%；
    color.green("开始清算程序！")
    await cErc20Delegator.liquidateBorrow(account.address, String(liquidateBorrow), cErc20Delegator.address,{gasLimit:30000000});

color.magenta(`
    account - erc20: ${formatUnits(await erc20Token.balanceOf(account.address))}
    account - 账户的存款额度(cToken)": ${formatUnits(await accountCToken.balanceOf(account.address))}
    account - 账户供应额度(标的资产)": ${formatUnits((await (await accountCToken.balanceOfUnderlying(account.address)).wait()).events[1].args[0])}`);
color.magenta(`
    signer - erc20: ${formatUnits(await erc20Token.balanceOf(signer.address))}
    signer - 账户的存款额度(cToken)": ${formatUnits(await cErc20Delegator.balanceOf(signer.address))} 
    signer - 账户供应额度(标的资产)": ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[1].args[0])}`);
    // color.magenta(`account - 账户的存款额度(cToken)": ${formatUnits(await accountCToken.balanceOf(signer.address))}`);


}


liquidateBorrow()
    .catch(err => console.log(err))