// compound 用户存款存款

// 用户先compound存入USDT, compound会根据当前的汇率算出铸造cUSDT的数量，将对应的cUSDT代币转移到用户账户中
import { createContracts } from "./contracts";
import address from "../abi/address.json";
const mint = async () => {
    const { compoundG7 } = await createContracts();
    console.log(compoundG7)
    // 部署抵押token
    await compoundG7.enterMarkets([
        address.cErc20Delegator,
        address.cEther
    ])

    
}


mint();

// const main = async () => {
//     const { compoundG7 } = await createContracts();
// }