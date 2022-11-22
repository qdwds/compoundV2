import { Contract } from "ethers";
import { createContracts } from "./contracts";


export const comptrollerStore = async () => {
    const { comptroller } = await createContracts();
    // await comptroller.
}

/**
 * 添加代币到市场中
 * @param cToken 要添加的cToken地址
 */
export const comptroller__supportMarket = async (cToken:string) =>{
    const { comptroller } = await createContracts();
    const tx = await comptroller._supportMarket(cToken).catch(err => console.log(err));
    console.log((await tx.wait()).logs);

}

/**
 * 用户把代币进入市场
 * @param cTokens 
 */
export const comptroller_enterMarkets = async (cTokens: Array<string>) => {
    const { comptroller } = await createContracts();
    await comptroller.enterMarkets(cTokens).catch(err => console.log(err));
    await comptroller_getAssetsIn();
}

/**
 * 获取用户加入市场的代币
 * @param owner 
 */
export const comptroller_getAssetsIn = async (owner?:string) => {
    const { comptroller, signer } = await createContracts();
    const reserves = await comptroller.getAssetsIn(owner||signer.address);
    console.log("用户加入市场的代币",reserves)



    
}
const main = async () => {

}