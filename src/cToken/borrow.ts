import { createContracts } from "../contracts";
import { formatUnits, parseEther, parseUnits } from "ethers/lib/utils";
import { color } from "../infomaction";
import { mint } from "./mint";


// 借款 标资产 USDT
const borrow = async () => {
    const { cErc20Delegator, signer } = await createContracts();
    // await mint("100")
    await cErc20Delegator.borrow(parseEther("500"));
}

borrow()
    .then(async _ => {
        const { cErc20Delegator, signer } = await createContracts();
        color.magenta(`borrow - 账户借款余额（含利息): ${formatUnits(await cErc20Delegator.borrowBalanceStored(signer.address))}`);
        color.magenta(`borrow - 账户的存款额度(cToken)": ${formatUnits(await cErc20Delegator.balanceOf(signer.address))}`);
        color.magenta(`borrow - 账户供应额度(标的资产)": ${formatUnits((await (await cErc20Delegator.balanceOfUnderlying(signer.address)).wait()).events[1].args[0])}`);

        color.magenta(`池子中 cToken总额度: ${formatUnits(await cErc20Delegator.totalSupply())}`)
        // color.magenta(`池子中 当前合约拥有标的资产的数量: ${formatUnits(await cErc20Delegator.getCashPrior())}`)
        color.magenta(`池子中 当前合约拥有标的资产的数量: ${formatUnits(await cErc20Delegator.getCash())}`)
        color.magenta(`池子中 市场总借款额度: ${formatUnits(await cErc20Delegator.totalBorrows())}`)
    })
.catch(err => console.log(err))