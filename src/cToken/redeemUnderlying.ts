import { createContracts } from "../contracts";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { color } from "../infomaction";
import { mint } from "./mint";


// 取款 输入`标的资产`数量算出cTokenr然后提取
const redeemUnderlying = async () => {
    const { cErc20Delegator, signer } = await createContracts();
    // await mint("100")
    const amount = await cErc20Delegator.redeemUnderlying(parseUnits("5"));
    await amount.wait();
    // const balance = await cErc20Delegator.getAccountSnapshot(signer.address);
    // console.log(balance);
}

redeemUnderlying()
    .then(async _=>{
        const { cErc20Delegator, signer } = await createContracts();
        color.magenta(`redeemUnderlying - 账户供应额度(cToken): ${formatUnits(await cErc20Delegator.balanceOf(signer.address))}`);
        color.magenta(`redeemUnderlying - 账户的存款额度(标的资产): ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[1].args[0])}`);
        color.magenta(`redeemUnderlying - 账户借款余额（含利息): ${formatUnits(await cErc20Delegator.borrowBalanceStored(signer.address))}`);
        // color.magenta(((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[1].args));
        // color.magenta(((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[0].args));
    })
    .catch(err => console.log(err))