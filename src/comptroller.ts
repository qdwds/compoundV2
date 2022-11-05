import { Contract } from "ethers";
import { createContracts } from "./contracts";


export const comptrollerStore = async () => {
    const { compoundG7 } = await createContracts();
    // await compoundG7.
}

/**
 * 添加代币到市场中
 * @param cToken 要添加的cToken地址
 */
export const comptrollerG7__supportMarket = async (cToken:string) =>{
    const { compoundG7 } = await createContracts();
    const tx = await compoundG7._supportMarket(cToken).catch(err => console.log(err));
    const a = await tx.wait();
    console.log(a.events);
}


export const comptrollerG7_enterMarkets = async (cTokens: Array<string>) => {
    const { compoundG7 } = await createContracts();
    await compoundG7.enterMarkets(cTokens).catch(err => console.log(err));
}

const main = async () => {

}