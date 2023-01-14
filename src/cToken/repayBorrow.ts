import { createContracts } from "../contracts";
import { formatUnits, parseEther } from "ethers/lib/utils";
import { color } from "../infomaction";


// 自己给自己还钱 USDT
const repayBorrow = async () => {
    const { cErc20Delegator, signer } = await createContracts();
    color.magenta(`repayBorrow - 账户借款余额（标的资产含利息): ${formatUnits(await cErc20Delegator.borrowBalanceStored(signer.address))}`);
    const transaction = await cErc20Delegator.repayBorrow(parseEther("5"), { gasLimit: 3000000 });
    await transaction.wait();
    color.magenta(`repayBorrow - 账户借款余额（标的资产含利息): ${formatUnits(await cErc20Delegator.borrowBalanceStored(signer.address))}`);
}

repayBorrow()
    .catch(err => console.log(err))