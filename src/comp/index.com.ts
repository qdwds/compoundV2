/**
 * setCompSpeedInternal 设置挖矿速率
 */
import { createContracts } from "../contracts";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";


// 存款 USDT
export const borrow = async () => {
    const { cErc20Delegator, erc20Token, comp, signer, comptroller } = await createContracts();
    const provider = new ethers.providers.JsonRpcProvider("http://localhost:8545");
    await comp.transfer(comptroller.address, parseUnits("10000"));
    // 开启挖矿奖励
    await comptroller._setCompSpeeds([cErc20Delegator.address],["0"],[parseUnits("2")]);
    await erc20Token.approve(cErc20Delegator.address, ethers.constants.MaxUint256)
    // await provider.send("evm_setIntervalMining", [1000]);
    await cErc20Delegator.mint(parseUnits("100"));
    await cErc20Delegator.borrow("100")
    await comptroller.updateCompBorrow(cErc20Delegator.address,signer.address);
    await comptroller.updateCompBorrow(cErc20Delegator.address,signer.address);
    await comptroller.updateCompBorrow(cErc20Delegator.address,signer.address);
    await comptroller.updateCompBorrow(cErc20Delegator.address,signer.address);
    console.log("signer comp 余额",formatUnits(await comp.balanceOf(signer.address)));
    console.log("signer comp 未提取额度", formatUnits(await comptroller.compAccrued(signer.address)));
    console.log("comptroller 总余额", formatUnits(await comp.balanceOf(comptroller.address)));
    await comptroller.getComp(signer.address, { gasLimit: 3000000 });
    console.log("signer comp 余额", formatUnits(await comp.balanceOf(signer.address)));
    console.log("signer comp 未提取额度", formatUnits(await comptroller.compAccrued(signer.address)));
    console.log("comptroller 总余额", formatUnits(await comp.balanceOf(comptroller.address)));
}

borrow()
    .catch(err => console.log(err));