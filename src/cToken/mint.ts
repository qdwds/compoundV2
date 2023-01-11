import { createContracts } from "../contracts";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { color } from "./infomaction";


// 存款
export const mint = async (money: string) => {
    const { cErc20Delegator, erc20Token } = await createContracts();
    await erc20Token.approve(cErc20Delegator.address, ethers.constants.MaxUint256)
    const a = await cErc20Delegator.mint(parseUnits(money));
    // const tx = await a.wait();
    // console.log(tx.events);
    
}

mint("1000")
    .then(async _ => {
        const { cErc20Delegator, signer } = await createContracts();
        color.magenta(`redeemUnderlying - 账户供应额度(cToken): ${formatUnits(await cErc20Delegator.balanceOf(signer.address))}`);
        color.magenta(`redeemUnderlying - 账户的存款额度(标的资产): ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[0].args[0])}`);
    })
    .catch(err => console.log(err))