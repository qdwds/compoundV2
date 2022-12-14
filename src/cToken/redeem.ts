import { createContracts } from "../contracts";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { color } from "./infomaction";
import { mint } from "./mint";


// 取款 输入cToken兑换标的资产数量
// 1标的资产 = 2个cToken
const redeem = async () => {
    const { cErc20Delegator, signer } = await createContracts();
    // await mint("100")
    const amountAll = await cErc20Delegator.redeem(parseUnits("50"));
    await amountAll.wait();
}

redeem()
    .then(async _=>{
        const { cErc20Delegator, signer } = await createContracts();
        color.magenta(`redeemUnderlying - 账户供应额度(cToken): ${formatUnits(await cErc20Delegator.balanceOf(signer.address))}`);
        color.magenta(`redeemUnderlying - 账户的存款额度(标的资产): ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[0].args[0])}`);
    })
    .catch(err => console.log(err))