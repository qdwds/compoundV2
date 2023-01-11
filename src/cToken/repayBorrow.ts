import { createContracts } from "../contracts";
import { formatUnits, parseEther } from "ethers/lib/utils";
import { color } from "./infomaction";


// 自己给自己换钱
const repayBorrow = async () => {
    const { cErc20Delegator, signer } = await createContracts();
    const transaction = await cErc20Delegator.repayBorrow(parseEther("25"));
    await transaction.wait();
    color.magenta(`repayBorrow - 账户借款余额（含利息: ${formatUnits(await cErc20Delegator.borrowBalanceStored(signer.address))}`);
}

repayBorrow()
    .catch(err => console.log(err))