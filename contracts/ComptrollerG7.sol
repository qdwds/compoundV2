pragma solidity ^0.5.16;

import "./CToken.sol";
import "./ErrorReporter.sol";
import "./PriceOracle.sol";
import "./ComptrollerInterface.sol";
import "./ComptrollerStorage.sol";
import "./Unitroller.sol";
import "./Governance/Comp.sol";
import "hardhat/console.sol";


/**
 * @title Compound's Comptroller Contract
 * @author Compound
 */
contract ComptrollerG7 is ComptrollerV5Storage, ComptrollerInterface, ComptrollerErrorReporter, ExponentialNoError {
    /// @notice Emitted when an admin supports a market
    event MarketListed(CToken cToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(CToken cToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(CToken cToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(uint oldCloseFactorMantissa, uint newCloseFactorMantissa);

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(CToken cToken, uint oldCollateralFactorMantissa, uint newCollateralFactorMantissa);

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(uint oldLiquidationIncentiveMantissa, uint newLiquidationIncentiveMantissa);

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(PriceOracle oldPriceOracle, PriceOracle newPriceOracle);

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(CToken cToken, string action, bool pauseState);

    /// @notice Emitted when a new COMP speed is calculated for a market
    event CompSpeedUpdated(CToken indexed cToken, uint newSpeed);

    /// @notice Emitted when a new COMP speed is set for a contributor
    event ContributorCompSpeedUpdated(address indexed contributor, uint newSpeed);

    /// @notice Emitted when COMP is distributed to a supplier
    event DistributedSupplierComp(CToken indexed cToken, address indexed supplier, uint compDelta, uint compSupplyIndex);

    /// @notice Emitted when COMP is distributed to a borrower
    event DistributedBorrowerComp(CToken indexed cToken, address indexed borrower, uint compDelta, uint compBorrowIndex);

    /// @notice Emitted when borrow cap for a cToken is changed
    event NewBorrowCap(CToken indexed cToken, uint newBorrowCap);

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(address oldBorrowCapGuardian, address newBorrowCapGuardian);

    /// @notice Emitted when COMP is granted by admin
    event CompGranted(address recipient, uint amount);

    /// @notice 市场的初始COMP指数
    uint224 public constant compInitialIndex = 1e36;

    // closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    constructor() public {
        admin = msg.sender;
    }

    /*** Assets You Are In ***/

    /**
      * @notice 返回账户的资产列表
      * @param account 拉取资产的账户地址
      * @return 账户输入资产的动态列表
      */
    //  获取当前用户有几种资产
    function getAssetsIn(address account) external view returns (CToken[] memory) {
        CToken[] memory assetsIn = accountAssets[account];
        return assetsIn;
    }

    /**
      * @notice 查询指定账户是否在指定资产中有额度
      * @param account 要检查的账户地址
      * @param cToken 需要检查的cToken
      * @return 如果帐户在资产中，则返回 True，否则返回 false。
      */

    function checkMembership(address account, CToken cToken) external view returns (bool) {
        return markets[address(cToken)].accountMembership[account];
    }

    /**
        * @notice 添加要包括在账户流动性计算中的资产
        * @param cTokens要启用的cToken市场地址列表
    */
    // * @return 是否进入每个相应市场的成功指标
    // 部署抵押token
    // 开启抵押
    function enterMarkets(address[] memory cTokens) public returns (uint[] memory) {
        uint len = cTokens.length;

        uint[] memory results = new uint[](len);
        for (uint i = 0; i < len; i++) {
            CToken cToken = CToken(cTokens[i]);

            results[i] = uint(addToMarketInternal(cToken, msg.sender));
        }

        return results;
    }

    /**
    * @notice 将市场添加到借款人的“资产”中, 进行流动性计算
    * @param cToken 要进入的市场
    * @param borrower 要修改的帐户地址
    */
    // * @return 是否进入市场的成功指标
    //  记录 借款人 开始借 cToken
    function addToMarketInternal(CToken cToken, address borrower) internal returns (Error) {
        // 用户cToken的资产数量
        Market storage marketToJoin = markets[address(cToken)];
        // console.log("sshagnshi",marketToJoin.isListed);
        // 检查代币是否上市
        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return Error.MARKET_NOT_LISTED;
        }

        // 检查当前账户是否有资产
        if (marketToJoin.accountMembership[borrower] == true) {
            // already joined
            // 已经加入
            return Error.NO_ERROR;
        }

        //经受住挑战，加入名单
        //注意：我们将这些存储在一定程度上冗余，作为一个重要的优化
        //这避免了必须遍历最常见用例的列表
        //也就是说，只有当我们需要执行流动性检查时
        //而不是每当我们想检查某个账户是否在某个特定市场时
        // 加入市场
        marketToJoin.accountMembership[borrower] = true;
        // 记录用户cToken加入市场的的address
        accountAssets[borrower].push(cToken);
        // console.log("accountAssets[borrower]", accountAssets[borrower]);
        emit MarketEntered(cToken, borrower);

        return Error.NO_ERROR;
    }

    /**
      * @notice 从发件人的账户流动性计算中删除资产
      * @dev 发件人不得在资产中有未偿还的借款余额，
      * 或为未偿还的借款提供必要的抵押品。
      * @param cTokenAddress 要移除的资产地址
      * @return 账户是否成功退市
      */
    function exitMarket(address cTokenAddress) external returns (uint) {
        CToken cToken = CToken(cTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the cToken */
        (uint oErr, uint tokensHeld, uint amountOwed, ) = cToken.getAccountSnapshot(msg.sender);
        require(oErr == 0, "exitMarket: getAccountSnapshot failed"); // semi-opaque error code

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
            return fail(Error.NONZERO_BORROW_BALANCE, FailureInfo.EXIT_MARKET_BALANCE_OWED);
        }

        /* Fail if the sender is not permitted to redeem all of their tokens */
        uint allowed = redeemAllowedInternal(cTokenAddress, msg.sender, tokensHeld);
        if (allowed != 0) {
            return failOpaque(Error.REJECTION, FailureInfo.EXIT_MARKET_REJECTION, allowed);
        }

        Market storage marketToExit = markets[address(cToken)];

        /* Return true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return uint(Error.NO_ERROR);
        }

        /* Set cToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete cToken from the account’s list of assets */
        // load into memory for faster iteration
        CToken[] memory userAssetList = accountAssets[msg.sender];
        uint len = userAssetList.length;
        uint assetIndex = len;
        for (uint i = 0; i < len; i++) {
            if (userAssetList[i] == cToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        CToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.length--;

        emit MarketExited(cToken, msg.sender);

        return uint(Error.NO_ERROR);
    }

    /*** Policy Hooks ***/

    /**
    * @notice 检查帐户是否应被允许在给定的市场中造币
    * @param cToken 验证造币厂的市场
    * @param minter 将获得铸造代币的帐户
    * @param mintAmount 提供给市场以换取代币的基础金额
    * 如果允许使用mint，@return 0，否则是一个半透明的错误代码（请参阅ErrorReporter.sol）
    */
    function mintAllowed(address cToken, address minter, uint mintAmount) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        // 检查是否有铸币权限
        require(!mintGuardianPaused[cToken], "mint is paused");

        // Shh - currently unused
        // 没有使用
        minter; //  铸币
        mintAmount; //  名称

        // 检查对应资产是否上市 ????????????????
        // 明明已经上市，为什么到这里数据是没有上市？？？？？？？？？？
        console.log("代币上市", markets[cToken].isListed);
        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);   //  error：市场没有上市
        }

        // Keep the flywheel moving
        // 更新指标
        updateCompSupplyIndex(cToken);
        // 更新分配代币奖励
        distributeSupplierComp(cToken, minter);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice 验证薄荷并在拒绝时恢复。 可能会发出日志。
      * @param cToken 资产被铸造
      * @param minter 铸造代币的地址
      * @param actualMintAmount 被铸造的标的资产的数量
      * @param mintTokens 正在铸造的代币数量
      */
    function mintVerify(address cToken, address minter, uint actualMintAmount, uint mintTokens) external {
        // Shh - currently unused
        cToken;
        minter;
        actualMintAmount;
        mintTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
    * @notice 检查账户是否应被允许在给定市场兑换代币
    * @param cToken 验证兑换的市场
    * @param redeemer 兑换者兑换代币的账户
    * @param redeemTokens 要在市场中交换基础资产的cTokens数量
    *如果允许兑换，@return 0，否则是一个半透明的错误代码（请参阅ErrorReporter.sol）
    */
    //  检查账户是否允许兑换
    function redeemAllowed(
        address cToken, //  cToken address
        address redeemer,   //  兑换账户地址
        uint redeemTokens   //  兑换cToken的数量
    ) external returns (uint) {
        uint allowed = redeemAllowedInternal(cToken, redeemer, redeemTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        // 更新指标
        updateCompSupplyIndex(cToken);
        // 更新奖励
        distributeSupplierComp(cToken, redeemer);

        return uint(Error.NO_ERROR);
    }

    // 是否允许兑换
    // 输入买入token合额度 计算流动性是否满足
    // 主要通过虚拟流动性 方式检查流动性是否充足
    function redeemAllowedInternal(
        address cToken,     // cToken地址
        address redeemer,   //  买入者地址
        uint redeemTokens   //  买入额度
    ) internal view returns (uint) {
        //  对应资产没有上市 返回错误
        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        // 用户 没有该资产返回错误 
        if (!markets[cToken].accountMembership[redeemer]) {
            return uint(Error.NO_ERROR);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        // 流动性检查 获取虚拟账户流动性内部
        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, CToken(cToken), redeemTokens, 0);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        // 流动性 > 0  返回流动性不足错误
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
    * @notice 验证兑换并在拒绝时回复。可能会发出日志。
    * @param cToken 资产正在赎回
    * @param redeemer 兑换者兑换代币的地址
    * @param redeemAmount 正在赎回的基础资产的金额
    * @param redeemTokens 正在兑换的代币数量
    */
    function redeemVerify(
        address cToken, 
        address redeemer, 
        uint redeemAmount, 
        uint redeemTokens
    ) external {
        // Shh - currently unused
        cToken;
        redeemer;

        // Require tokens is zero or amount is also zero
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    /**
    * @notice 检查账户是否应被允许借入给定市场的基础资产
    * @param cToken 验证借款的市场
    * @param borrower 将借入资产的账户
    * @param borrowAmount 账户将借入的基础金额
    * @return 0（如果允许借用），否则返回一个半透明的错误代码（请参阅ErrorReporter.sol）
    */
    //  检查账户是否允许借钱
    function borrowAllowed(
        address cToken,     //  借什么token
        address borrower,   //  借款地址
        uint borrowAmount   //  借款数量
    ) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        // 是否拥有借款权限
        require(!borrowGuardianPaused[cToken], "borrow is paused");
        
        // 检查代币是否上市
        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }
        // 检查当前账户是否有资产
        if (!markets[cToken].accountMembership[borrower]) {
            // 如果借款人不在市场上，只有cToken可以调用borrowAllowed
            // console.log("msg.sender", msg.sender);
            // console.log("cToken", cToken);
            require(msg.sender == cToken, "sender must be cToken");

            // attempt to add borrower to the market
            // 把用户到 cToken  加入到市场中 。
            Error err = addToMarketInternal(CToken(msg.sender), borrower);
            if (err != Error.NO_ERROR) {
                return uint(err);
            }

            // it should be impossible to break the important invariant
            // 检查用户是否有资产
            assert(markets[cToken].accountMembership[borrower]);
        }

        // 获取价格
        if (oracle.getUnderlyingPrice(CToken(cToken)) == 0) {
            return uint(Error.PRICE_ERROR);
        }

        // 借款额度
        uint borrowCap = borrowCaps[cToken];
        console.log("borrowCap", borrowCap);
        // 借款上限0对应于无限借款
        if (borrowCap != 0) {
            // 借款总量
            uint totalBorrows = CToken(cToken).totalBorrows();
            // 借款总量 + 当前用户借款额度
            uint nextTotalBorrows = add_(totalBorrows, borrowAmount);
            require(nextTotalBorrows < borrowCap, "market borrow cap reached");
        }

        // 计算流动性
        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(borrower, CToken(cToken), 0, borrowAmount);
        console.log("shortfall", shortfall);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        console.log("是否允许借钱流动性",shortfall);
        // 总借款额度 流动性不足
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        // Keep the flywheel moving
        Exp memory borrowIndex = Exp({mantissa: CToken(cToken).borrowIndex()});
        // 更新指数
        updateCompBorrowIndex(cToken, borrowIndex);
        // 更新奖励
        distributeBorrowerComp(cToken, borrower, borrowIndex);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates borrow and reverts on rejection. May emit logs.
     * @param cToken Asset whose underlying is being borrowed
     * @param borrower The address borrowing the underlying
     * @param borrowAmount The amount of the underlying asset requested to borrow
     */
    function borrowVerify(address cToken, address borrower, uint borrowAmount) external {
        // Shh - currently unused
        cToken;
        borrower;
        borrowAmount;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
      * @notice 检查是否应允许帐户在给定市场偿还借款
      * @param cToken 验证还款的市场
      * @param payer 偿还资产的账户
      * @param borrower 借入资产的账户
      * @param repayAmount 账户将偿还的标的资产的金额
      * @return 如果允许还款，则返回 0，否则为半透明错误代码（参见 ErrorReporter.sol）
      */
    //  检查账户是否允许还款
    function repayBorrowAllowed(
        address cToken,
        address payer,
        address borrower,
        uint repayAmount
    ) external returns (uint) {
        // Shh - currently unused
        payer;
        borrower;
        repayAmount;
        // 检查是否上市
        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        // Keep the flywheel moving
        // 获取还款人 借款时候的指数
        Exp memory borrowIndex = Exp({mantissa: CToken(cToken).borrowIndex()});
        console.log("borrowIndex 还款人借款时候的指数", borrowIndex.mantissa);
        // 更新指数
        updateCompBorrowIndex(cToken, borrowIndex);
        // 更新奖励 借款人补偿
        distributeBorrowerComp(cToken, borrower, borrowIndex);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice 验证 repayBorrow 并在拒绝时恢复。 可能会发出日志。
      * @param cToken 资产被偿还
      * @param payer 还款地址
      * @param borrower 借款人地址
      * @param actualRepayAmount 被偿还的标的金额
      * @param borrowerIndex 借款人索引
      */
    function repayBorrowVerify(
        address cToken,
        address payer,
        address borrower,
        uint actualRepayAmount,
        uint borrowerIndex
    ) external {
        // Shh - currently unused
        cToken;
        payer;
        borrower;
        actualRepayAmount;
        borrowerIndex;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
      * @notice 检查是否应该允许清算发生
      * @param cTokenBorrowed 借款人借入的资产
      * @param cTokenCollateral 资产被用作抵押品，将被没收
      * @param liquidator 清算人 偿还借款和扣押抵押品的地址
      * @param borrower 借款人地址
      * @param repayAmount 被偿还的标的金额
      */
    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount
    ) external returns (uint) {
        // Shh - currently unused
        liquidator;

        // 借入的资产和被抵押的资产必须上市
        if (!markets[cTokenBorrowed].isListed || !markets[cTokenCollateral].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* The borrower must have shortfall in order to be liquidatable */
        // 获取流动性
        (Error err, , uint shortfall) = getAccountLiquidityInternal(borrower);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        // 流动性枯竭
        if (shortfall == 0) {
            return uint(Error.INSUFFICIENT_SHORTFALL);
        }

        /* 清算人不得偿还超过 closeFactor 允许的金额 */
        // 获取借款人的余额
        uint borrowBalance = CToken(cTokenBorrowed).borrowBalanceStored(borrower);
        console.log("borrowBalance 借款人借入额度", borrowBalance);
        // 最多只能清算借款人  50% 债务
        // 如果我清算完再清算呢？？？？
        uint maxClose = mul_ScalarTruncate(Exp({mantissa: closeFactorMantissa}), borrowBalance);
        //  单比交易的清算额度不能大于最大清算量
        if (repayAmount > maxClose) {
            return uint(Error.TOO_MUCH_REPAY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice 验证liquidateBorrow 并在拒绝时恢复。 可能会发出日志。
      * @param cTokenBorrowed 借款人借入的资产
      * @param cTokenCollateral 资产被用作抵押品，将被没收
      * @param liquidator 偿还借款和扣押抵押品的地址
      * @param borrower 借款人地址
      * @param actualRepayAmount 被偿还的标的金额
      */
    //  审计合约审计是否清算成功
    function liquidateBorrowVerify(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint actualRepayAmount,
        uint seizeTokens
    ) external {
        // Shh - currently unused
        cTokenBorrowed;
        cTokenCollateral;
        liquidator;
        borrower;
        actualRepayAmount;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
      * @notice 检查是否应允许扣押资产
      * @param cTokenCollateral 资产被用作抵押品，将被没收
      * @param cTokenBorrowed 借款人借入的资产
      * @param liquidator 偿还借款和扣押抵押品的地址
      * @param borrower 借款人地址
      * @param seizeTokens 要没收的抵押代币数量
      */
    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        // 检查系统是否开启 抵押抵押品功能
        require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;
        // 检查抵押品是否上市 和 借入的资产是否上市
        if (!markets[cTokenCollateral].isListed || !markets[cTokenBorrowed].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }
        // 没有找到对应变量 函数
        // console.log("CToken(cTokenCollateral.comptroller())", CToken(cTokenCollateral.comptroller()));
        // console.log("CToken(cTokenCollateral.cTokenBorrowed())", CToken(cTokenCollateral.cTokenBorrowed()));

        // 两个审计地址不能相同？？？
        if (CToken(cTokenCollateral).comptroller() != CToken(cTokenBorrowed).comptroller()) {
            return uint(Error.COMPTROLLER_MISMATCH);
        }

        // Keep the flywheel moving
        // 更新指数
        updateCompSupplyIndex(cTokenCollateral);
        // 更新两个cToken奖励
        distributeSupplierComp(cTokenCollateral, borrower);
        distributeSupplierComp(cTokenCollateral, liquidator);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice 验证抓住并在拒绝时恢复。 可能会发出日志。
      * @param cTokenCollateral 资产被用作抵押品，将被没收
      * @param cTokenBorrowed 借款人借入的资产
      * @param liquidator 偿还借款和扣押抵押品的地址
      * @param borrower 借款人地址
      * @param seizeTokens 要没收的抵押代币数量
      */
    function seizeVerify(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external {
        // Shh - currently unused
        cTokenCollateral;
        cTokenBorrowed;
        liquidator;
        borrower;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

   /**
    * @notice 检查是否应允许帐户在给定市场中转移代币
    * @param cToken 验证转账的市场
    * @param src 获取代币的账户
    * @param dst 接收代币的账户
    * @param transferTokens 要转移的 cToken 数量
    * @return 0 如果允许传输，否则为半透明错误代码（参见 ErrorReporter.sol）
    */
    function transferAllowed(
        address cToken, 
        address src, 
        address dst, 
        uint transferTokens
    ) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        // 暂停转账功能
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        // 通过传入的价格计算流动性，返回是否可以购买
        uint allowed = redeemAllowedInternal(cToken, src, transferTokens);
        console.log("allowed", allowed);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        // 更新指标
        updateCompSupplyIndex(cToken);
        // 更新 获取的代币
        distributeSupplierComp(cToken, src);
        // 更新 接收代币
        distributeSupplierComp(cToken, dst);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates transfer and reverts on rejection. May emit logs.
     * @param cToken Asset being transferred
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of cTokens to transfer
     */
    function transferVerify(address cToken, address src, address dst, uint transferTokens) external {
        // Shh - currently unused
        cToken;
        src;
        dst;
        transferTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /*** Liquidity/Liquidation Calculations ***/

    /**
      * @dev 用于在计算账户流动性时避免堆栈深度限制的本地变量。
      * 请注意，`cTokenBalance` 是该账户在市场上拥有的 cToken 数量，
      * 而 `borrowBalance` 是账户借入的标的资产的数量。
      */
    struct AccountLiquidityLocalVars {
        uint sumCollateral;
        uint sumBorrowPlusEffects;
        uint cTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissa;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePrice;
        Exp tokensToDenom;
    }

    /**
      * @notice 确定当前账户流动性 wrt 抵押品要求
      * return（可能的错误代码（半透明），
                 账户流动性超过抵押品要求，
      * 账户余额低于抵押要求）
      */
    // 获取账户流动性
    // 账户流动性是指用户供应余额的总值减去该用户借款余额的总值，再乘以协议抵押品比率。
    // 账户流动性为负数的用户将无法提取或借入任何资产，直到其账户流动性恢复到正数。
    // 这可以通过向协议提供更多的资产或偿还任何未偿还的借款资产来实现。账户流动性为负值，也意味着用户的账户将被清算。
    // 查询待清算账户
    function getAccountLiquidity(address account) public view returns (uint, uint, uint) {
        (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(account, CToken(0), 0, 0);

        return (uint(err), liquidity, shortfall);
    }

    /**
      * @notice 确定当前账户流动性 wrt 抵押品要求
      */
    //   * @return（可能的错误代码，账户流动性超过抵押品要求，账户余额低于抵押要求）
    function getAccountLiquidityInternal(address account) internal view returns (Error, uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, CToken(0), 0, 0);
    }

    /**
      * @notice 确定如果给定金额被赎回/借入，账户流动性将是多少
      * @param cTokenModify 假设赎回/借入的市场
      * @param account 确定流动性的账户
      * @param redeemTokens 假设要赎回的代币数量
      * @param borrowAmount 假设借入的底层证券数量
      * return（可能的错误代码（半透明），
                 假设账户流动性超过抵押品要求，
      * 假设账户缺口低于抵押要求）
      */
    function getHypotheticalAccountLiquidity(
        address account,
        address cTokenModify,
        uint redeemTokens,
        uint borrowAmount) public view returns (uint, uint, uint) {
        (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(account, CToken(cTokenModify), redeemTokens, borrowAmount);
        return (uint(err), liquidity, shortfall);
    }

    /**
    * @notice 确定如果给定金额被赎回/借入，账户流动性将是多少
    * @param cTokenModify 假设赎回/借入的市场
    * @param account 确定流动性的账户
    * @param redeemTokens 假设要赎回的代币数量
    * @param borrowAmount 假设借入的底层证券数量
    * @dev 请注意，我们使用存储的数据计算每个抵押 cToken 的 exchangeRateStored，不计算累积利息。
    假设账户流动性超过抵押品要求，
    *假设账户缺口低于抵押要求）
    */
    // * @return（可能的错误代码，
   //   通过给定金额 计算虚拟流动性
    function getHypotheticalAccountLiquidityInternal(
        address account,
        CToken cTokenModify,
        uint redeemTokens,
        uint borrowAmount
    ) internal view returns (Error, uint, uint) {

        AccountLiquidityLocalVars memory vars; // 获取计算结果
        uint oErr;

        // For each asset the account is in
        // 获取用户的资产，不区分存借款
        CToken[] memory assets = accountAssets[account];
        for (uint i = 0; i < assets.length; i++) {
            CToken asset = assets[i];

            // Read the balances and exchange rate from the cToken
            // 从 cToken 中读取余额和汇率
            (
                oErr, 
                vars.cTokenBalance,     //  用户余额
                vars.borrowBalance,     //  存款额度
                vars.exchangeRateMantissa   //  存款时候的汇率
            ) = asset.getAccountSnapshot(account);
            // 返回错误
            if (oErr != 0) { // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (Error.SNAPSHOT_ERROR, 0, 0);
            }
            // 抵押率
            vars.collateralFactor = Exp({mantissa: markets[address(asset)].collateralFactorMantissa});
            //  存款时候的汇率
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // 获取cToken资产价格
            vars.oraclePriceMantissa = oracle.getUnderlyingPrice(asset);
            if (vars.oraclePriceMantissa == 0) {
                return (Error.PRICE_ERROR, 0, 0);
            }
            // 设置cToken资产价格
            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});

            // 从代币->以太（标准化价格值）预计算转换因子
            // 价格因子 = (抵押率 * 存款汇率) * 价格
            vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);
            
            // mul_ScalarTruncateAddUInt 公式  a * b + c;
            
            // sumCollateral += tokensToDenom * cTokenBalance
            // 获取总价值 = 价格因子 * 用户token总量
            vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.cTokenBalance, vars.sumCollateral);
            console.log("vars.sumCollateral", vars.sumCollateral);

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            // 总借款额度 += 预言价格 * 借款额度
            vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);
            console.log("vars.sumBorrowPlusEffects", vars.sumBorrowPlusEffects);

            // Calculate effects of interacting with cTokenModify
            if (asset == cTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);
                // console.log("vars.sumBorrowPlusEffects", vars.sumBorrowPlusEffects);
                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);
                // console.log("vars.sumBorrowPlusEffects", vars.sumBorrowPlusEffects);
            }
        }

        // These are safe, as the underflow condition is checked first
        // console.log("vars.sumCollateral > vars.sumBorrowPlusEffects","总抵押额度", vars.sumCollateral);
        // console.log( "总借款额度",vars.sumBorrowPlusEffects);
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            // 借款额度
            // console.log("vars.sumCollateral - vars.sumBorrowPlusEffects, 0", vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
            return (Error.NO_ERROR, vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        } else {
            //  清算
            // console.log("0, vars.sumBorrowPlusEffects - vars.sumCollateral", 0, vars.sumBorrowPlusEffects - vars.sumCollateral);
            return (Error.NO_ERROR, 0, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    /**
      * @notice 计算给定标的金额要扣押的抵押资产代币数量
      * @dev 用于清算（在 cToken.liquidateBorrowFresh 中调用）
      * @param cTokenBorrowed 借来的 cToken 地址
      * @param cTokenCollateral 抵押品cToken的地址
      * @param actualRepayAmount cTokenBorrowed 标的转换为 cTokenCollateral 代币的数量
      * @return (errorCode, 清算中要扣押的 cTokenCollateral 代币数量)
      */
    //  根据给定的金额计算抵押品的数量
    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,     //  借款人的地址
        address cTokenCollateral,   //  抵押品地址
        uint actualRepayAmount      //  金额 => 抵押品数量
    ) external view returns (uint, uint) {
        /* Read oracle prices for borrowed and collateral markets */
        // 获取token价格
        uint priceBorrowedMantissa = oracle.getUnderlyingPrice(CToken(cTokenBorrowed));
        uint priceCollateralMantissa = oracle.getUnderlyingPrice(CToken(cTokenCollateral));
        // 价格有一个为0的是返回价格错误
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint(Error.PRICE_ERROR), 0);
        }

        /*
          * 获取汇率并计算扣押的抵押代币数量：
          *seizeAmount = actualRepayAmount *liquidationIncentive * priceBorrowed / priceCollateral
          * 抓住令牌 = 抓住数量 / 兑换率
          * = 实际还款金额 * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
          */
        //  获取 抵押品汇率
        uint exchangeRateMantissa = CToken(cTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint seizeTokens;
        Exp memory numerator;   //  分子
        Exp memory denominator; //  分母
        Exp memory ratio;       //  比率
        // 分子 = 清算激励 * 借款cToken的价格
        numerator = mul_(Exp({mantissa: liquidationIncentiveMantissa}), Exp({mantissa: priceBorrowedMantissa}));
        // denominator = 抵押品价格 * 抵押平汇率
        denominator = mul_(Exp({mantissa: priceCollateralMantissa}), Exp({mantissa: exchangeRateMantissa}));
        // 比率 = 分子 - 分母
        ratio = div_(numerator, denominator);
        // 清算资产数量 = 比率 * 抵押品金额额度
        seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);
        console.log("seizeTokens 清算资产数量为", seizeTokens);
        return (uint(Error.NO_ERROR), seizeTokens);
    }

    /*** Admin Functions ***/
    /*** 管理员函数 ***/
    /**
       * @notice 为主计长设置新的价格预言机
       * @dev 管理员功能设置新的价格预言机
       * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
       */
    function _setPriceOracle(PriceOracle newOracle) public returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PRICE_ORACLE_OWNER_CHECK);
        }
        // console.log(newOracle);
        // Track the old oracle for the comptroller
        PriceOracle oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice 设置清算借款时使用的closeFactor
      * @dev Admin函数设置closeFactor
      * @param newCloseFactorMantissa 新关闭因子，按1e18缩放
      * @return uint 0=成功，否则失败
    */
    //   设置清算比例
    //  50%，即：0.5 * 1 ^18 = 500000000000000000
    function _setCloseFactor(uint newCloseFactorMantissa) external returns (uint) {
        // Check caller is admin
    	require(msg.sender == admin, "only admin can set close factor");

        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        // console.log("closeFactorMantissa", closeFactorMantissa);
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
       * @notice 设置市场的抵押因子
       * @dev 管理功能设置每个市场的抵押因子
       * @param cToken 设置因子的市场
       * @param newCollateralFactorMantissa 新的抵押因子，按 1e18 缩放
       * @return uint 0=成功，否则失败。 （有关详细信息，请参阅错误报告器）
       */
    //  设置抵押率
    function _setCollateralFactor(CToken cToken, uint newCollateralFactorMantissa) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COLLATERAL_FACTOR_OWNER_CHECK);
        }

        // Verify market is listed
        Market storage market = markets[address(cToken)];
        if (!market.isListed) {
            return fail(Error.MARKET_NOT_LISTED, FailureInfo.SET_COLLATERAL_FACTOR_NO_EXISTS);
        }

        Exp memory newCollateralFactorExp = Exp({mantissa: newCollateralFactorMantissa});

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({mantissa: collateralFactorMaxMantissa});
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            return fail(Error.INVALID_COLLATERAL_FACTOR, FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION);
        }

        // If collateral factor != 0, fail if price == 0
        if (newCollateralFactorMantissa != 0 && oracle.getUnderlyingPrice(cToken) == 0) {
            return fail(Error.PRICE_ERROR, FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE);
        }

        // Set market's collateral factor to new collateral factor, remember old value
        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(cToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
       * @notice 设置清算激励
       * @dev 管理员功能设置清算激励
       * @param newLiquidationIncentiveMantissa 新的清算激励按 1e18 缩放
       * @return uint 0=成功，否则失败。 （有关详细信息，请参阅错误报告器）
       */
    //  设置流动性激励为 8%，参数值就是1.08 * 1 ^ 18;
    function _setLiquidationIncentive(uint newLiquidationIncentiveMantissa) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_LIQUIDATION_INCENTIVE_OWNER_CHECK);
        }

        // Save current value for use in log
        uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;
        // console.log("liquidationIncentiveMantissa", liquidationIncentiveMantissa);
        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
       * @notice 将市场添加到市场映射并将其设置为列出
       * @dev 管理员功能设置 isListed 并添加对市场的支持
       * @param cToken 要上市的市场（token）地址
       * @return uint 0=成功，否则失败。 （详见枚举错误）
       */
    //  
    function _supportMarket(CToken cToken) external returns (uint) {
        // 只有管理员才能开启上市
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SUPPORT_MARKET_OWNER_CHECK);
        }
        console.log("shi", markets[address(cToken)].isListed);
        // 已经上市 返回错误
        if (markets[address(cToken)].isListed) {
            console.log("已经上市");
            return fail(Error.MARKET_ALREADY_LISTED, FailureInfo.SUPPORT_MARKET_EXISTS);
        }

        // 检查是否为cToken
        cToken.isCToken(); // Sanity check to make sure its really a CToken

        // // Note that isComped is not in active use anymore
        markets[address(cToken)] = Market({
            isListed: true, //  上市
            isComped: false,
            collateralFactorMantissa: 0    //  抵押率
        });
        // Note that isComped is not in active use anymore
        // Market storage market = markets[address(cToken)];
        // market.isListed = true;
        // market.isComped = false;
        // market.collateralFactorMantissa = 0;
        
        console.log( markets[address(cToken)].isListed);
        // 添加到市场中
        _addMarketInternal(address(cToken));

        emit MarketListed(cToken);

        return uint(Error.NO_ERROR);
    }
    // 添加cToken到市场中
    function _addMarketInternal(address cToken) internal {
        // 循环所有市场 存在的话报错是为了防止重复添加
        for (uint i = 0; i < allMarkets.length; i ++) {
            require(allMarkets[i] != CToken(cToken), "market already added");
        }
        // 添加到市场
        allMarkets.push(CToken(cToken));
    }


    /**
       * @notice 为给定的 cToken 市场设置给定的借贷上限。 使借款总额达到或超过借款上限的借款将恢复。
       * @dev Admin 或 borrowCapGuardian 函数设置借用上限。 借款上限为 0 对应于无限制借款。
       * @param cTokens 用于更改借贷上限的市场（代币）地址
       * @param newBorrowCaps 要设置的底层证券的新借入上限值。 值 0 对应于无限借用。
       */
    //   设计借款额度上限，到达借款额度上限后无法在借出额度
    function _setMarketBorrowCaps(
        CToken[] calldata cTokens, 
        uint[] calldata newBorrowCaps
    ) external {
        // borrowCapGuardian  可以设置借款上限的管理员
    	require(msg.sender == admin || msg.sender == borrowCapGuardian, "only admin or borrow cap guardian can set borrow caps"); 

        uint numMarkets = cTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        // 检查市场中的cToken数量，
        require(numMarkets != 0 && numMarkets == numBorrowCaps, "invalid input");

        for(uint i = 0; i < numMarkets; i++) {
            // 设置cToken 借款上限
            borrowCaps[address(cTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(cTokens[i], newBorrowCaps[i]);
        }
    }

    /**
      * @notice 管理员功能更改借用上限监护人
      * @param newBorrowCapGuardian 新借款上限监护人的地址
      */
    //  设置可以设置借款上限的管理员地址
    function _setBorrowCapGuardian(address newBorrowCapGuardian) external {
        require(msg.sender == admin, "only admin can set borrow cap guardian");

        // Save current value for inclusion in log
        address oldBorrowCapGuardian = borrowCapGuardian;

        // Store borrowCapGuardian with value newBorrowCapGuardian
        borrowCapGuardian = newBorrowCapGuardian;

        // Emit NewBorrowCapGuardian(OldBorrowCapGuardian, NewBorrowCapGuardian)
        emit NewBorrowCapGuardian(oldBorrowCapGuardian, newBorrowCapGuardian);
    }

    /**
      * @notice 管理员功能更改暂停守护者
      * @param newPauseGuardian 新暂停守护者的地址
      * @return uint 0=成功，否则失败。 （详见枚举错误）
      */
    //  设置可以暂停的管理员地址地址
    function _setPauseGuardian(address newPauseGuardian) public returns (uint) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PAUSE_GUARDIAN_OWNER_CHECK);
        }

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);

        return uint(Error.NO_ERROR);
    }

    function _setMintPaused(CToken cToken, bool state) public returns (bool) {
        require(markets[address(cToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        mintGuardianPaused[address(cToken)] = state;
        emit ActionPaused(cToken, "Mint", state);
        return state;
    }

    function _setBorrowPaused(CToken cToken, bool state) public returns (bool) {
        require(markets[address(cToken)].isListed, "cannot pause a market that is not listed");
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        borrowGuardianPaused[address(cToken)] = state;
        emit ActionPaused(cToken, "Borrow", state);
        return state;
    }
    
    // 开启关闭转账功能
    function _setTransferPaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function _setSeizePaused(bool state) public returns (bool) {
        require(msg.sender == pauseGuardian || msg.sender == admin, "only pause guardian and admin can pause");
        require(msg.sender == admin || state == true, "only admin can unpause");

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    // 设置代理合约地址
    function _become(Unitroller unitroller) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        require(unitroller._acceptImplementation() == 0, "change not authorized");
    }

    /**
     * @notice Checks caller is admin, or this contract is becoming the new implementation
     */
    function adminOrInitializing() internal view returns (bool) {
        return msg.sender == admin || msg.sender == comptrollerImplementation;
    }

    /*** Comp Distribution ***/
    /*** 奖励分配 */
    /**
      * @notice 为单个市场设置 COMP 速度
      * @param cToken COMP 更新速度的市场
      * @param compSpeed 市场的新 COMP 速度
      */
    function setCompSpeedInternal(CToken cToken, uint compSpeed) internal {
        uint currentCompSpeed = compSpeeds[address(cToken)];
        // currentCompSpeed == 0,说明没有设置速率。
        if (currentCompSpeed != 0) {
            // note that COMP speed could be set to 0 to halt liquidity rewards for a market
            // 获取当前cToken指数
            Exp memory borrowIndex = Exp({mantissa: cToken.borrowIndex()});
            // 更新指数
            updateCompSupplyIndex(address(cToken));
            updateCompBorrowIndex(address(cToken), borrowIndex);
        } 
        // 要设置新的速率 != 0
        else if (compSpeed != 0) {
            // Add the COMP market
            Market storage market = markets[address(cToken)];
            require(market.isListed == true, "comp market is not listed");

            if (compSupplyState[address(cToken)].index == 0 && compSupplyState[address(cToken)].block == 0) {
                compSupplyState[address(cToken)] = CompMarketState({
                    index: compInitialIndex,
                    block: safe32(getBlockNumber(), "block number exceeds 32 bits")
                });
            }

            if (compBorrowState[address(cToken)].index == 0 && compBorrowState[address(cToken)].block == 0) {
                compBorrowState[address(cToken)] = CompMarketState({
                    index: compInitialIndex,
                    block: safe32(getBlockNumber(), "block number exceeds 32 bits")
                });
            }
        }
        // 之前存储的速率和新速率不相等的时候重新设置速率
        if (currentCompSpeed != compSpeed) {
            compSpeeds[address(cToken)] = compSpeed;
            emit CompSpeedUpdated(cToken, compSpeed);
        }
    }

    /**
    * @notice 通过更新供应指数将 COMP 计入市场
    * @param cToken 要更新其供应指数的市场
    */
    //  更新token得指数
    function updateCompSupplyIndex(address cToken) internal {
        // 获取cToken在市场中的供应状态
        CompMarketState storage supplyState = compSupplyState[cToken];
        uint supplySpeed = compSpeeds[cToken];
        console.log("supplySpeed", supplySpeed);
        // 当前区块
        uint blockNumber = getBlockNumber();
        //  获取当前区块合之前更新区块之间相差的区块数量
        uint deltaBlocks = sub_(blockNumber, uint(supplyState.block));
        console.log("deltaBlocks 相差区块数量", deltaBlocks);
        // 相差区块 和 市场供应存储的区块(有一种可能就是新市场供应可能是0)
        // 市场供应：有一种可能就是新市场供应可能是0
        // 相差区块：有一种可能之前更新过
        // 所以两个都需要判断大于0
        if (deltaBlocks > 0 && supplySpeed > 0) {
            // 处理已经上市的区块

            // cToken流通总量
            uint supplyTokens = CToken(cToken).totalSupply();
            // 流通量 * 区块数量
            uint compAccrued = mul_(deltaBlocks, supplySpeed);
            // 计算代币总量？？？ 计算出来 更新了多少指数
            Double memory ratio = supplyTokens > 0 ? fraction(compAccrued, supplyTokens) : Double({mantissa: 0});
            console.log("ratio.mantissa", ratio.mantissa);

            // 最新指数 = 之前index  + ratio
            Double memory index = add_(Double({mantissa: supplyState.index}), ratio);
            //  更新当前 cToken的指数和区块
            compSupplyState[cToken] = CompMarketState({
                index: safe224(index.mantissa, "new index exceeds 224 bits"),
                block: safe32(blockNumber, "block number exceeds 32 bits")
            });
        } else if (deltaBlocks > 0) {
            // 不需要更新指数？？？
            // 更新传入的cToken区块数据
            supplyState.block = safe32(blockNumber, "block number exceeds 32 bits");
        }
    }

    /**
     * @notice Accrue COMP to the market by updating the borrow index
     * @param cToken The market whose borrow index to update
     */
    function updateCompBorrowIndex(address cToken, Exp memory marketBorrowIndex) internal {
        CompMarketState storage borrowState = compBorrowState[cToken];
        uint borrowSpeed = compSpeeds[cToken];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = sub_(blockNumber, uint(borrowState.block));
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint borrowAmount = div_(CToken(cToken).totalBorrows(), marketBorrowIndex);
            uint compAccrued = mul_(deltaBlocks, borrowSpeed);
            Double memory ratio = borrowAmount > 0 ? fraction(compAccrued, borrowAmount) : Double({mantissa: 0});
            Double memory index = add_(Double({mantissa: borrowState.index}), ratio);
            compBorrowState[cToken] = CompMarketState({
                index: safe224(index.mantissa, "new index exceeds 224 bits"),
                block: safe32(blockNumber, "block number exceeds 32 bits")
            });
        } else if (deltaBlocks > 0) {
            borrowState.block = safe32(blockNumber, "block number exceeds 32 bits");
        }
    }

    /**
    * @notice 计算调用者应计的 COMP 并可能将其转移给他们
    * @param cToken 调用者互动的市场
    * @param supplier 将 COMP 分发到的调用者地址
    */
    //  当前用户此前未结算的存款产出的 COMP
    function distributeSupplierComp(address cToken, address supplier) internal {
        // 获取comp供应状态
        CompMarketState storage supplyState = compSupplyState[cToken];
        // 获取当前指数
        Double memory supplyIndex = Double({mantissa: supplyState.index});
        // 获取最后一次的指数数值
        Double memory supplierIndex = Double({mantissa: compSupplierIndex[cToken][supplier]});
        // 更新指数
        compSupplierIndex[cToken][supplier] = supplyIndex.mantissa;
        // 最后一次指数 == 0 && 当前指数大于 0  === 新添加的
        if (supplierIndex.mantissa == 0 && supplyIndex.mantissa > 0) {
            // 赋值初始化指数
            supplierIndex.mantissa = compInitialIndex;
        }
        // 当前指数 - 最后一次更新指数 == 相差指数
        Double memory deltaIndex = sub_(supplyIndex, supplierIndex);
        // 获取调用者的额度
        uint supplierTokens = CToken(cToken).balanceOf(supplier);
        console.log("supplierTokens", supplierTokens);
        // 调用者额度 * 相差指数 = 奖励的数量
        uint supplierDelta = mul_(supplierTokens, deltaIndex);
        console.log("supplierDelta", supplierDelta);
        // 未提现 + 奖励数量 = 总奖励(未体现)
        uint supplierAccrued = add_(compAccrued[supplier], supplierDelta);
        console.log("supplierAccrued", supplierAccrued);
        // 更新当前用户的奖励COMP
        compAccrued[supplier] = supplierAccrued;
        emit DistributedSupplierComp(CToken(cToken), supplier, supplierDelta, supplyIndex.mantissa);
    }

    /**
      * @notice 计算借款人累积的 COMP 并可能将其转移给他们
      * @dev 借款人在与协议第一次交互之后才会开始累积。
      * @param cToken 借款人互动的市场
      * @param borrower 要分配 COMP 的借款人的地址
      */
    function distributeBorrowerComp(address cToken, address borrower, Exp memory marketBorrowIndex) internal {
        CompMarketState storage borrowState = compBorrowState[cToken];
        Double memory borrowIndex = Double({mantissa: borrowState.index});
        Double memory borrowerIndex = Double({mantissa: compBorrowerIndex[cToken][borrower]});
        compBorrowerIndex[cToken][borrower] = borrowIndex.mantissa;

        if (borrowerIndex.mantissa > 0) {
            Double memory deltaIndex = sub_(borrowIndex, borrowerIndex);
            uint borrowerAmount = div_(CToken(cToken).borrowBalanceStored(borrower), marketBorrowIndex);
            uint borrowerDelta = mul_(borrowerAmount, deltaIndex);
            uint borrowerAccrued = add_(compAccrued[borrower], borrowerDelta);
            compAccrued[borrower] = borrowerAccrued;
            emit DistributedBorrowerComp(CToken(cToken), borrower, borrowerDelta, borrowIndex.mantissa);
        }
    }

    /**
      * @notice 计算自上次应计以来贡献者的额外应计 COMP
      * @param contributor 计算贡献者奖励的地址
      */
    function updateContributorRewards(address contributor) public {
        uint compSpeed = compContributorSpeeds[contributor];
        uint blockNumber = getBlockNumber();
        uint deltaBlocks = sub_(blockNumber, lastContributorBlock[contributor]);
        if (deltaBlocks > 0 && compSpeed > 0) {
            uint newAccrued = mul_(deltaBlocks, compSpeed);
            uint contributorAccrued = add_(compAccrued[contributor], newAccrued);

            compAccrued[contributor] = contributorAccrued;
            lastContributorBlock[contributor] = blockNumber;
        }
    }

    /**
      * @notice 索取持有人在所有市场中累积的所有补偿
      * @param holder 申请 COMP 的地址
      */
    // 提取奖励的COMP token  -  前提需要开启存取款奖励(_setCompSpeed 函数)
    function claimComp(address holder) public {
        return claimComp(holder, allMarkets);
    }

    /**
      * @notice 索取持有人在指定市场获得的所有补偿
      * @param holder 申请 COMP 的地址
      * @param cTokens 要求 COMP 的市场列表
      */
    // 提取奖励的COMP token  -  前提需要开启存取款奖励(_setCompSpeed 函数)
    function claimComp(address holder, CToken[] memory cTokens) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimComp(holders, cTokens, true, true);
    }

   /**
      * @notice 索取持有人应得的所有补偿
      * @param holders 申请 COMP 的地址
      * @param cTokens 要求 COMP 的市场列表
      * @param borrowers 是否领取通过借款赚取的 COMP
      * @param suppliers 供应商是否要求通过供应获得的 COMP
      */
    // 提取奖励的COMP token  -  前提需要开启存取款奖励(_setCompSpeed 函数)
    function claimComp(address[] memory holders, CToken[] memory cTokens, bool borrowers, bool suppliers) public {
        for (uint i = 0; i < cTokens.length; i++) {
            CToken cToken = cTokens[i];
            require(markets[address(cToken)].isListed, "market must be listed");
            if (borrowers == true) {
                Exp memory borrowIndex = Exp({mantissa: cToken.borrowIndex()});
                updateCompBorrowIndex(address(cToken), borrowIndex);
                for (uint j = 0; j < holders.length; j++) {
                    distributeBorrowerComp(address(cToken), holders[j], borrowIndex);
                    compAccrued[holders[j]] = grantCompInternal(holders[j], compAccrued[holders[j]]);
                }
            }
            if (suppliers == true) {
                updateCompSupplyIndex(address(cToken));
                for (uint j = 0; j < holders.length; j++) {
                    distributeSupplierComp(address(cToken), holders[j]);
                    compAccrued[holders[j]] = grantCompInternal(holders[j], compAccrued[holders[j]]);
                }
            }
        }
    }

    /**
      * @notice 将 COMP 转移给用户
      * @dev 注意：如果没有足够的 COMP，我们不会全部执行传输。
      * @param user 将 COMP 转入的用户地址
      * @param amount 要（可能）转账的 COMP 数量
      * @return 未转给用户的 COMP 数量
      */
    function grantCompInternal(address user, uint amount) internal returns (uint) {
        Comp comp = Comp(getCompAddress());
        uint compRemaining = comp.balanceOf(address(this));
        if (amount > 0 && amount <= compRemaining) {
            comp.transfer(user, amount);
            return 0;
        }
        return amount;
    }

    /*** Comp Distribution Admin ***/
    /*** 管理员调用的 奖励分配函数 ***/
    /**
      * @notice 将 COMP 转给收件人
      * @dev 注意：如果没有足够的 COMP，我们不会全部执行传输。
      * @param recipient 将 COMP 转入的收件人地址
      * @param amount 要（可能）转账的 COMP 数量
      */
    function _grantComp(address recipient, uint amount) public {
        require(adminOrInitializing(), "only admin can grant comp");
        uint amountLeft = grantCompInternal(recipient, amount);
        require(amountLeft == 0, "insufficient comp for grant");
        emit CompGranted(recipient, amount);
    }

    /**
      * @notice 为单个市场设置 COMP 速度
      * @param cToken COMP 更新速度的市场
      * @param compSpeed 市场的新 COMP 速度
      */
    //  设置token奖励 可以自己单独设置某些cToken|cEth 有奖励
    // 用户存和借cToken都会有奖励，如果cToken市场设置了compSpeed。compSpeed： 整数，表示协议将COMP分配给市场供应商或借款人的速率。价值是分配给市场的每个区块的COMP（单位：wei）
    function _setCompSpeed(CToken cToken, uint compSpeed) public {
        // 读取每个以太坊区块分配到单个市场的COMP量
        require(adminOrInitializing(), "only admin can set comp speed");
        setCompSpeedInternal(cToken, compSpeed);
    }

    /**
      * @notice 为单个贡献者设置 COMP 速度
      * @param contributor 贡献者 COMP 更新速度的贡献者
      * @param compSpeed 贡献者的新 COMP 速度
      */
    function _setContributorCompSpeed(address contributor, uint compSpeed) public {
        require(adminOrInitializing(), "only admin can set comp speed");

        // note that COMP speed could be set to 0 to halt liquidity rewards for a contributor
        updateContributorRewards(contributor);
        if (compSpeed == 0) {
            // release storage
            delete lastContributorBlock[contributor];
        } else {
            lastContributorBlock[contributor] = getBlockNumber();
        }
        compContributorSpeeds[contributor] = compSpeed;

        emit ContributorCompSpeedUpdated(contributor, compSpeed);
    }

   /**
      * @notice 返回所有市场
      * @dev 自动获取器可用于访问单个市场。
      * @return 市场地址列表
      */
    function getAllMarkets() public view returns (CToken[] memory) {
        return allMarkets;
    }

    function getBlockNumber() public view returns (uint) {
        return block.number;
    }

    /**
      * @notice 返回 COMP 令牌的地址
      * @return COMP 的地址
      */
    function getCompAddress() public pure returns (address) {
        return /**start*/0x6b39b761b1b64C8C095BF0e3Bb0c6a74705b4788/**end*/;
    }
}