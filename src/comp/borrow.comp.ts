/**
 * setCompSpeedInternal 设置挖矿速率
 */
import { createContracts } from "../contracts";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";


// 存款 USDT
export const borrow = async () => {
    const { cErc20Delegator, erc20Token, signer, comptroller } = await createContracts();
    const provider = new ethers.providers.JsonRpcProvider("http://localhost:8545");

    // 开启挖矿奖励
    await comptroller._setCompSpeeds([cErc20Delegator.address],[0],[parseUnits("2")]);
    await erc20Token.approve(cErc20Delegator.address, ethers.constants.MaxUint256)
    // await provider.send("evm_setIntervalMining", [1000]);
    await cErc20Delegator.mint(parseUnits("100"));
    await cErc20Delegator.borrow("100")
    setInterval(async()=>{
        console.log(await provider.getBlockNumber())
        await comptroller.updateCompBorrow(cErc20Delegator.address,signer.address);
        console.log(formatUnits(await comptroller.compAccrued(signer.address)));
    },1000)
}

borrow()
    .catch(err => console.log(err));