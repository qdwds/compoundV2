import { formatUnits, parseEther } from "ethers/lib/utils";
import { createContracts } from "../contracts";

/**
 * comp :1
 * comp :2 
 * comp :3
 */
const claimComp = async () => {
    const { comp , signer, comptroller, cErc20Delegator } = await createContracts();
    await comp.transfer(comptroller.address, parseEther("10000"));
    console.log("signer comp 余额",formatUnits(await comp.balanceOf(signer.address)));
    console.log("signer comp 未提取额度", formatUnits(await comptroller.compAccrued(signer.address)));
    console.log("comptroller 总余额", formatUnits(await comp.balanceOf(comptroller.address)));

    console.log(comptroller.claimComp);
    await comptroller.getComp(signer.address, { gasLimit: 3000000 });

    console.log("signer comp 余额", formatUnits(await comp.balanceOf(signer.address)));
    console.log("signer comp 未提取额度", formatUnits(await comptroller.compAccrued(signer.address)));
    console.log("comptroller 总余额", formatUnits(await comp.balanceOf(comptroller.address)));

}

claimComp()
    .catch(err => console.log(err));