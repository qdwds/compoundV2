/**
 * setCompSpeedInternal 设置挖矿速率
 */
import { createContracts } from "../contracts";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";


// 存款 USDT
export const mint = async (money: string) => {
    const { cErc20Delegator, erc20Token, signer, comptroller } = await createContracts();
    console.log(comptroller);
    return
    // 开启挖矿奖励
    await comptroller._setCompSpeeds(cErc20Delegator,parseUnits("10"),parseUnits("20"));
    await erc20Token.approve(cErc20Delegator.address, ethers.constants.MaxUint256)
    await cErc20Delegator.mint(parseUnits("100"));
    setInterval(()=>{
        console.log(comptroller.compAccrued(signer.address));
    },1000)
}

mint()
    .catch(err => console.log(err));