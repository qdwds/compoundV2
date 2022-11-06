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
}

/**
 * 用户把代币进入市场
 * @param cTokens 
 */
export const comptrollerG7_enterMarkets = async (cTokens: Array<string>) => {
    const { compoundG7 } = await createContracts();
    await compoundG7.enterMarkets(cTokens).catch(err => console.log(err));
    await comptrollerG7_getAssetsIn();
}

/**
 * 获取用户加入市场的代币
 * @param owner 
 */
export const comptrollerG7_getAssetsIn = async (owner?:string) => {
    const { compoundG7, signer } = await createContracts();
    const reserves = await compoundG7.getAssetsIn(owner||signer.address);
    console.log("用户加入市场的代币",reserves)



    
}
const main = async () => {

}