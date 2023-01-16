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
// 审计合约，对存取款等操作审计和校验
contract Comptroller is ComptrollerV7Storage, ComptrollerInterface, ComptrollerErrorReporter, ExponentialNoError {
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

    /// @notice Emitted when a new borrow-side COMP speed is calculated for a market
    event CompBorrowSpeedUpdated(CToken indexed cToken, uint newSpeed);

    /// @notice Emitted when a new supply-side COMP speed is calculated for a market
    event CompSupplySpeedUpdated(CToken indexed cToken, uint newSpeed);

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

    /// @notice  市场的初始COMP指数
    uint224 public constant compInitialIndex = 1e36;

    // closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.9e18; // 0.9

    // comp address 
    address public comAddress;
    constructor() public {
        admin = msg.sender;
    }

    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) external view returns (CToken[] memory) {
        CToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param cToken The cToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, CToken cToken) external view returns (bool) {
        return markets[address(cToken)].accountMembership[account];
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param cTokens The list of addresses of the cToken markets to be enabled
     * @return Success indicator for whether each corresponding market was entered
     */
    // 对已经在市场的资产进行 开启 作为抵押品操作
    // 将指定多个ctoken 做为抵押品，对应的增加用户的可借额度
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
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param cToken The market to enter
     * @param borrower The address of the account to modify
     * @return Success indicator for whether the market was entered
     */
    function addToMarketInternal(CToken cToken, address borrower) internal returns (Error) {
        Market storage marketToJoin = markets[address(cToken)];

        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return Error.MARKET_NOT_LISTED;
        }

        if (marketToJoin.accountMembership[borrower] == true) {
            // already joined
            return Error.NO_ERROR;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(cToken);

        emit MarketEntered(cToken, borrower);

        return Error.NO_ERROR;
    }

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param cTokenAddress The address of the asset to be removed
     * @return Whether or not the account successfully exited the market
     */
    //  // 对已经在市场的资产进行 关闭 作为抵押品操作
    // 将指定的ctoken从抵押品中移除。但是如果用户在借款时，exitMarket的资产价值不能超过借款价值，用户的抵押品会存储accountAssets中。
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
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param cToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    // 是否允许存款
    function mintAllowed(address cToken, address minter, uint mintAmount) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[cToken], "mint is paused");

        // Shh - currently unused
        minter;
        mintAmount;
        // console.log(!markets[cToken].isListed);
        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        // Keep the flywheel moving
        updateCompSupplyIndex(cToken);
        distributeSupplierComp(cToken, minter);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates mint and reverts on rejection. May emit logs.
     * @param cToken Asset being minted
     * @param minter The address minting the tokens
     * @param actualMintAmount The amount of the underlying asset being minted
     * @param mintTokens The number of tokens being minted
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
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param cToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of cTokens to exchange for the underlying asset in the market
     * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    // 是否允许取款
    function redeemAllowed(address cToken, address redeemer, uint redeemTokens) external returns (uint) {
        uint allowed = redeemAllowedInternal(cToken, redeemer, redeemTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updateCompSupplyIndex(cToken);
        distributeSupplierComp(cToken, redeemer);

        return uint(Error.NO_ERROR);
    }

    function redeemAllowedInternal(address cToken, address redeemer, uint redeemTokens) internal view returns (uint) {
        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!markets[cToken].accountMembership[redeemer]) {
            return uint(Error.NO_ERROR);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, CToken(cToken), redeemTokens, 0);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param cToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(address cToken, address redeemer, uint redeemAmount, uint redeemTokens) external {
        // Shh - currently unused
        cToken;
        redeemer;

        // Require tokens is zero or amount is also zero
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param cToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @return 0 if the borrow is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    // 
    // 是否允许借款
    function borrowAllowed(address cToken, address borrower, uint borrowAmount) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!borrowGuardianPaused[cToken], "borrow is paused");
        // console.log("!markets[cToken].isListed");
        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        if (!markets[cToken].accountMembership[borrower]) {
            // only cTokens may call borrowAllowed if borrower not in market
            require(msg.sender == cToken, "sender must be cToken");

            // attempt to add borrower to the market
            Error err = addToMarketInternal(CToken(msg.sender), borrower);
            if (err != Error.NO_ERROR) {
                return uint(err);
            }

            // it should be impossible to break the important invariant
            assert(markets[cToken].accountMembership[borrower]);
        }
        //  获取cToken价格
        if (oracle.getUnderlyingPrice(CToken(cToken)) == 0) {
            return uint(Error.PRICE_ERROR);
        }


        uint borrowCap = borrowCaps[cToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint totalBorrows = CToken(cToken).totalBorrows();
            uint nextTotalBorrows = add_(totalBorrows, borrowAmount);
            require(nextTotalBorrows < borrowCap, "market borrow cap reached");
        }

        (Error err, , uint shortfall) = getHypotheticalAccountLiquidityInternal(borrower, CToken(cToken), 0, borrowAmount);
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        console.log("允许借款流动性",shortfall);
        // 流动性不足
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        // Keep the flywheel moving
        Exp memory borrowIndex = Exp({mantissa: CToken(cToken).borrowIndex()});
        updateCompBorrowIndex(cToken, borrowIndex);
        // 更新借款 挖款奖励
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
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param cToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     * @return 0 if the repay is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    // 是否允许还款
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
        // 是否上市
        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        // Keep the flywheel moving
        Exp memory borrowIndex = Exp({mantissa: CToken(cToken).borrowIndex()});
        updateCompBorrowIndex(cToken, borrowIndex);
        distributeBorrowerComp(cToken, borrower, borrowIndex);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates repayBorrow and reverts on rejection. May emit logs.
     * @param cToken Asset being repaid
     * @param payer The address repaying the borrow
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function repayBorrowVerify(
        address cToken,
        address payer,
        address borrower,
        uint actualRepayAmount,
        uint borrowerIndex) external {
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
     * @notice Checks if the liquidation should be allowed to occur
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    // 是否允许清算
    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount) external returns (uint) {
        // Shh - currently unused
        liquidator;
        // 检查两个代币是否上市
        if (!markets[cTokenBorrowed].isListed || !markets[cTokenCollateral].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }
        //  获取借款人余额
        uint borrowBalance = CToken(cTokenBorrowed).borrowBalanceStored(borrower);

        /* allow accounts to be liquidated if the market is deprecated */
        // 判断是否是否被弃用 如果市场被弃用，允许清算账户
        if (isDeprecated(CToken(cTokenBorrowed))) {
            // 不能偿还超过借款总额
            require(borrowBalance >= repayAmount, "Can not repay more than the total borrow");
        } else {
            /* The borrower must have shortfall in order to be liquidatable */
            // 获取流动性
            (Error err, , uint shortfall) = getAccountLiquidityInternal(borrower);
            if (err != Error.NO_ERROR) {
                return uint(err);
            }
            // console.log("是否允许清算流动性：",shortfall);
            // 流动性不足   判断是允许清算。只要  != 0 就是允许清算的。
            if (shortfall == 0) {
                console.log("流动性不足，不能清算!");
                return uint(Error.INSUFFICIENT_SHORTFALL);
            }

            /* The liquidator may not repay more than what is allowed by the closeFactor */
            // 清算人不得偿还超过 closeFactor 允许的数额 50%
            uint maxClose = mul_ScalarTruncate(Exp({mantissa: closeFactorMantissa}), borrowBalance);
            // 清算额度超过计算额度  返回错误
            // console.log(repayAmount,maxClose);
            if (repayAmount > maxClose) {
                return uint(Error.TOO_MUCH_REPAY);
            }
        }
        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates liquidateBorrow and reverts on rejection. May emit logs.
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    //  审计合约审计是否清算成功
    function liquidateBorrowVerify(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint actualRepayAmount,
        uint seizeTokens) external {
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
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    // 是否允许清算抵押物
    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;

        if (!markets[cTokenCollateral].isListed || !markets[cTokenBorrowed].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        if (CToken(cTokenCollateral).comptroller() != CToken(cTokenBorrowed).comptroller()) {
            return uint(Error.COMPTROLLER_MISMATCH);
        }

        // Keep the flywheel moving
        updateCompSupplyIndex(cTokenCollateral);
        distributeSupplierComp(cTokenCollateral, borrower);
        distributeSupplierComp(cTokenCollateral, liquidator);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates seize and reverts on rejection. May emit logs.
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeVerify(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens) external {
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
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param cToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of cTokens to transfer
     * @return 0 if the transfer is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    // 是否允许转账
    function transferAllowed(address cToken, address src, address dst, uint transferTokens) external returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        uint allowed = redeemAllowedInternal(cToken, src, transferTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        // Keep the flywheel moving
        updateCompSupplyIndex(cToken);
        distributeSupplierComp(cToken, src);
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
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `cTokenBalance` is the number of cTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
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
      * @notice 确定当前账户流动性wrt抵押品要求
      * return（可能的错误代码（半不透明），
                 超过抵押品要求的账户流动性，
      * 低于抵押品要求的账户差额）
      */
    // 获取用户的资产状况
    function getAccountLiquidity(address account) public view returns (uint, uint, uint) {
        // liquidity 剩余的可借额度(用户抵押的总价值)
        // 
        (Error err, uint liquidity, uint shortfall) = getHypotheticalAccountLiquidityInternal(account, CToken(0), 0, 0);

        return (uint(err), liquidity, shortfall);
    }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code,
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternal(address account) internal view returns (Error, uint, uint) {
        return getHypotheticalAccountLiquidityInternal(account, CToken(0), 0, 0);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param cTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (possible error code (semi-opaque),
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
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
      * @param redeemTokens 假设赎回的代币数量
      * @param borrowAmount 假设借入的基础资产数量
      * @dev 请注意，我们使用存储的数据为每个抵押品 cToken 计算 exchangeRateStored，
      * 不计算累积利息。
      * return（可能的错误代码，
                 假设账户流动性超过抵押品要求，
      * 假设账户缺口低于抵押品要求）
      */
    // 计算当前用户的总持仓资产价值 是否大于总借贷价值
    function getHypotheticalAccountLiquidityInternal(
        address account,    //  查询的用户
        CToken cTokenModify,    //  cToken
        uint redeemTokens,  //  假设赎回的代币数量
        uint borrowAmount   //  假设介入的代币数量
    ) internal view returns (Error, uint, uint) {

        // 保存数据
        AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint oErr;

        // For each asset the account is in
        CToken[] memory assets = accountAssets[account];
        
        for (uint i = 0; i < assets.length; i++) {
            CToken asset = assets[i];
            // console.log("asset",address(asset));
            // Read the balances and exchange rate from the cToken

            // 获取当前用户中的cToken中的信息
            (oErr, 
                vars.cTokenBalance, //  cToken额度
                vars.borrowBalance, //  借款额度
                vars.exchangeRateMantissa   //  汇率
            ) = asset.getAccountSnapshot(account);
            if (oErr != 0) { // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (Error.SNAPSHOT_ERROR, 0, 0);
            }
            // 获取用户资产抵押率
            vars.collateralFactor = Exp({mantissa: markets[address(asset)].collateralFactorMantissa});
            // 汇率
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            // 获取当前资产的价格
            vars.oraclePriceMantissa = oracle.getUnderlyingPrice(asset);
            if (vars.oraclePriceMantissa == 0) {
                return (Error.PRICE_ERROR, 0, 0);
            }// 设置价格
            vars.oraclePrice = Exp({mantissa: vars.oraclePriceMantissa});

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            // 从代币 -> 以太币（标准化价格值）预先计算一个转换因子
            // 单个货币价值？ =（资产抵押率 * 汇率） * 价格
            vars.tokensToDenom = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);
            // console.log("vars.sumCollateral 总抵押品",vars.sumCollateral);
            // sumCollateral += tokensToDenom * cTokenBalance
            // 单个货币价值 * cToken额度 + 总抵押品 = 总抵押品
            vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.cTokenBalance, vars.sumCollateral);
            // console.log("vars.sumCollateral 总抵押品",vars.sumCollateral);

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            // 借款额度 = 价格 * 借款数量
            vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);

            // Calculate effects of interacting with cTokenModify
            // 当前货币 = 借入资产
            if (asset == cTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);
            }
        }

        // These are safe, as the underflow condition is checked first
        // liquidity 剩余的可借额度 (总抵押 - 总债务)
        // shortfall 可以清算  (总债务 - 总抵押)
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            // console.log("vars.sumCollateral - vars.sumBorrowPlusEffects",vars.sumCollateral - vars.sumBorrowPlusEffects);
            return (Error.NO_ERROR, vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
        } else {
            // console.log("vars.sumBorrowPlusEffects - vars.sumCollateral", vars.sumBorrowPlusEffects - vars.sumCollateral);
            return (Error.NO_ERROR, 0, vars.sumBorrowPlusEffects - vars.sumCollateral);
        }
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in cToken.liquidateBorrowFresh)
     * @param cTokenBorrowed The address of the borrowed cToken
     * @param cTokenCollateral The address of the collateral cToken
     * @param actualRepayAmount The amount of cTokenBorrowed underlying to convert into cTokenCollateral tokens
     * @return (errorCode, number of cTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(address cTokenBorrowed, address cTokenCollateral, uint actualRepayAmount) external view returns (uint, uint) {
        /* Read oracle prices for borrowed and collateral markets */
        uint priceBorrowedMantissa = oracle.getUnderlyingPrice(CToken(cTokenBorrowed));
        uint priceCollateralMantissa = oracle.getUnderlyingPrice(CToken(cTokenCollateral));
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint(Error.PRICE_ERROR), 0);
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint exchangeRateMantissa = CToken(cTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint seizeTokens;
        Exp memory numerator;
        Exp memory denominator;
        Exp memory ratio;

        numerator = mul_(Exp({mantissa: liquidationIncentiveMantissa}), Exp({mantissa: priceBorrowedMantissa}));
        denominator = mul_(Exp({mantissa: priceCollateralMantissa}), Exp({mantissa: exchangeRateMantissa}));
        ratio = div_(numerator, denominator);

        seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);

        return (uint(Error.NO_ERROR), seizeTokens);
    }

    /*** Admin Functions ***/

    /**
       * @notice 为审计员设置一个新的价格预言机
       * @dev Admin 函数设置一个新的价格预言机
       * @return uint 0=成功，否则失败（详见ErrorReporter.sol）
       */
    //  价格预言机
    function _setPriceOracle(PriceOracle newOracle) public returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PRICE_ORACLE_OWNER_CHECK);
        }

        // Track the old oracle for the comptroller
        PriceOracle oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets the closeFactor used when liquidating borrows
      * @dev Admin function to set closeFactor
      * @param newCloseFactorMantissa New close factor, scaled by 1e18
      * @return uint 0=success, otherwise a failure
      */
    //  关闭质押因子
    function _setCloseFactor(uint newCloseFactorMantissa) external returns (uint) {
        // Check caller is admin
    	require(msg.sender == admin, "only admin can set close factor");

        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
       * @notice 设置市场的 collateralFactor
       * @dev Admin 函数来设置每个市场的抵押品因子
       * @param cToken 设置因子的市场
       * @param newCollateralFactorMantissa 新的抵押因子，按 1e18 缩放
       * @return uint 0=成功，否则失败。 （详见 ErrorReporter）
       */
    //  开启质押因子
    // 设置资产抵押率
    function _setCollateralFactor(CToken cToken, uint newCollateralFactorMantissa) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_COLLATERAL_FACTOR_OWNER_CHECK);
        }

        // Verify market is listed
        // 检查是否上市
        Market storage market = markets[address(cToken)];
        if (!market.isListed) {
            return fail(Error.MARKET_NOT_LISTED, FailureInfo.SET_COLLATERAL_FACTOR_NO_EXISTS);
        }

        Exp memory newCollateralFactorExp = Exp({mantissa: newCollateralFactorMantissa});

        // Check collateral factor <= 0.9
        // 检查抵押因子 <= 0.9
        Exp memory highLimit = Exp({mantissa: collateralFactorMaxMantissa});
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            return fail(Error.INVALID_COLLATERAL_FACTOR, FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION);
        }

        // If collateral factor != 0, fail if price == 0
        // 如果抵押因子 != 0，如果价格 == 0 则失败
        if (newCollateralFactorMantissa != 0 && oracle.getUnderlyingPrice(cToken) == 0) {
            return fail(Error.PRICE_ERROR, FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE);
        }

        // Set market's collateral factor to new collateral factor, remember old value
        // 将市场的抵押品因子设置为新的抵押品因子，记住旧值
        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        // 触发事件
        emit NewCollateralFactor(cToken, oldCollateralFactorMantissa, newCollateralFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Sets liquidationIncentive
      * @dev Admin function to set liquidationIncentive
      * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
      * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
      */
    function _setLiquidationIncentive(uint newLiquidationIncentiveMantissa) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_LIQUIDATION_INCENTIVE_OWNER_CHECK);
        }

        // Save current value for use in log
        uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Add the market to the markets mapping and set it as listed
      * @dev Admin function to set isListed and add support for the market
      * @param cToken The address of the market (token) to list
      * @return uint 0=success, otherwise a failure. (See enum Error for details)
      */
    //  设置借贷资产资产哪些资产的存借。
    function _supportMarket(CToken cToken) external returns (uint) {
        if (msg.sender != admin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SUPPORT_MARKET_OWNER_CHECK);
        }

        if (markets[address(cToken)].isListed) {
            return fail(Error.MARKET_ALREADY_LISTED, FailureInfo.SUPPORT_MARKET_EXISTS);
        }

        cToken.isCToken(); // Sanity check to make sure its really a CToken

        // Note that isComped is not in active use anymore
        // markets 市场支持的token 存入这个数据结构中。
        markets[address(cToken)] = Market({isListed: true, isComped: false, collateralFactorMantissa: 0});

        _addMarketInternal(address(cToken));
        _initializeMarket(address(cToken));

        emit MarketListed(cToken);

        return uint(Error.NO_ERROR);
    }

    function _addMarketInternal(address cToken) internal {
        for (uint i = 0; i < allMarkets.length; i ++) {
            require(allMarkets[i] != CToken(cToken), "market already added");
        }
        allMarkets.push(CToken(cToken));
        console.log("markets[address(cToken)].isListed",address(cToken),markets[address(cToken)].isListed);
    }

    // 初始化市场
    function _initializeMarket(address cToken) internal {
        uint32 blockNumber = safe32(getBlockNumber(), "block number exceeds 32 bits");
        
        // 获取市场comp供应率
        CompMarketState storage supplyState = compSupplyState[cToken];
        CompMarketState storage borrowState = compBorrowState[cToken];

        /*
         * Update market state indices
         */
        // 判断使用率是否为0
        if (supplyState.index == 0) {
            // 使用默认值初始化供应状态索引
            supplyState.index = compInitialIndex;
        }

        if (borrowState.index == 0) {
            // 使用默认值初始化供应状态索引
            borrowState.index = compInitialIndex;
        }

        /*
         * Update market state block numbers
         */
        // 更新为最新区块
        supplyState.block = borrowState.block = blockNumber;
    }


    /**
      * @notice Set the given borrow caps for the given cToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
      * @dev Admin or borrowCapGuardian function to set the borrow caps. A borrow cap of 0 corresponds to unlimited borrowing.
      * @param cTokens The addresses of the markets (tokens) to change the borrow caps for
      * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
      */
    //  设计借款额度上限，到达借款额度上限后无法在借出额度
    function _setMarketBorrowCaps(CToken[] calldata cTokens, uint[] calldata newBorrowCaps) external {
    	require(msg.sender == admin || msg.sender == borrowCapGuardian, "only admin or borrow cap guardian can set borrow caps"); 

        uint numMarkets = cTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        require(numMarkets != 0 && numMarkets == numBorrowCaps, "invalid input");

        for(uint i = 0; i < numMarkets; i++) {
            borrowCaps[address(cTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(cTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Borrow Cap Guardian
     * @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
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
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    //  设置可以暂停的地址
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

    function _become(Unitroller unitroller) public {
        require(msg.sender == unitroller.admin(), "only unitroller admin can change brains");
        require(unitroller._acceptImplementation() == 0, "change not authorized");
    }

    /**
     * @notice Checks caller is admin, or this contract is becoming the new implementation
     */
    // 判断是否为管理员或者审计长
    function adminOrInitializing() internal view returns (bool) {
        return msg.sender == admin || msg.sender == comptrollerImplementation;
    }

    /*** Comp Distribution ***/

    /**
      * @notice 为单一市场设置 COMP 速度
      * @param cToken COMP 更新速度的市场
      * @param supplySpeed 新的供应方 COMP 市场速度
      * @param borrowSpeed 市场的新借方 COMP 速度
      */
    // 设置存款/借款 两个挖款速率（每个区块） wei
    function setCompSpeedInternal(
        CToken cToken, 
        uint supplySpeed, 
        uint borrowSpeed
    ) internal {
        // 检查是否上市。
        Market storage market = markets[address(cToken)];
        require(market.isListed, "comp market is not listed");
        //  存款挖款速率
        // 1 != 2
        if (compSupplySpeeds[address(cToken)] != supplySpeed) {
            // 供应速度已更新所以让我们更新供应状态以确保
            // 1. COMP 为旧速度正确累积，并且
            // 2. 在此块之后开始以新速度累积的 COMP。
            // 更新存款指数
            updateCompSupplyIndex(address(cToken));

            // Update speed and emit event
            compSupplySpeeds[address(cToken)] = supplySpeed;
            emit CompSupplySpeedUpdated(cToken, supplySpeed);
        }
        // 借款挖款速率
        if (compBorrowSpeeds[address(cToken)] != borrowSpeed) {
            // 借用速度已更新所以让我们更新借用状态以确保
            // 1. COMP 为旧速度正确累积，并且
            // 2. 在此块之后开始以新速度累积的 COMP。
            Exp memory borrowIndex = Exp({mantissa: cToken.borrowIndex()});
            // 更新借款指数
            updateCompBorrowIndex(address(cToken), borrowIndex);

            // Update speed and emit event
            compBorrowSpeeds[address(cToken)] = borrowSpeed;
            emit CompBorrowSpeedUpdated(cToken, borrowSpeed);
        }
    }

    /**
      * @notice 通过更新供应指数将 COMP 计入市场
      * @param cToken 要更新供应指数的市场
      * @dev 指数是每个 cToken 累积的 COMP 的总和。
      */
    //  存款挖款
    function updateCompSupplyIndex(address cToken) internal {
        // 获取cToken的供应状态
        CompMarketState storage supplyState = compSupplyState[cToken];
        // 每个区块的供应状态
        uint supplySpeed = compSupplySpeeds[cToken];
        // 区块超过32位
        uint32 blockNumber = safe32(getBlockNumber(), "block number exceeds 32 bits");
        // console.log("blockNumber",blockNumber);
        // 新增区块
        uint deltaBlocks = sub_(uint(blockNumber), uint(supplyState.block));
        // console.log("deltaBlocks",deltaBlocks);
        // 新增区块和供应区块都大于0 说明不是同一个区块
        if (deltaBlocks > 0 && supplySpeed > 0) {
            // cToken总量
            uint supplyTokens = CToken(cToken).totalSupply();
            // 新区块 * 每个区块挖矿速率
            uint compAccrued = mul_(deltaBlocks, supplySpeed);
            Double memory ratio = supplyTokens > 0 ?
                fraction(compAccrued, supplyTokens) :
                Double({mantissa: 0});
            supplyState.index = safe224(add_(Double({mantissa: supplyState.index}), ratio).mantissa, "new index exceeds 224 bits");
            supplyState.block = blockNumber;
        } 
        // 只有新增区块大于0 更新 供应区块 = 当前区块。
        else if (deltaBlocks > 0) {
            supplyState.block = blockNumber;
        }
    }

    /**
      * @notice 通过更新借入指数将 COMP 计入市场
      * @param cToken 要更新借入指数的市场
      * @dev 指数是每个 cToken 累积的 COMP 的总和。
      */
    //  借款挖款
    function updateCompBorrowIndex(address cToken, Exp memory marketBorrowIndex) internal {
        CompMarketState storage borrowState = compBorrowState[cToken];
        uint borrowSpeed = compBorrowSpeeds[cToken];
        uint32 blockNumber = safe32(getBlockNumber(), "block number exceeds 32 bits");
        uint deltaBlocks = sub_(uint(blockNumber), uint(borrowState.block));
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            uint borrowAmount = div_(CToken(cToken).totalBorrows(), marketBorrowIndex);
            uint compAccrued = mul_(deltaBlocks, borrowSpeed);
            Double memory ratio = borrowAmount > 0 ? fraction(compAccrued, borrowAmount) : Double({mantissa: 0});
            borrowState.index = safe224(add_(Double({mantissa: borrowState.index}), ratio).mantissa, "new index exceeds 224 bits");
            borrowState.block = blockNumber;
        } else if (deltaBlocks > 0) {
            borrowState.block = blockNumber;
        }
    }

    /**
      * @notice 计算供应商应计的 COMP 并可能将其转移给他们
      * @param cToken 供应商正在互动的市场
      * @param supplier 将 COMP 分配给的供应商的地址
      */
    //  分发当前用户此前未结算的存款产出的 COMP
    // 计算存款 当前未产出的COMP，只是更新当前用户的COMP数量，并未发送给用户
    function distributeSupplierComp(address cToken, address supplier) internal {
        // TODO：如果用户不在供应商市场，则不要分发供应商 COMP。
         // 由于在许多地方调用了 distributeSupplierComp，因此此检查应尽可能节省 gas。
         // - 我们真的不想调用外部合约，因为它非常昂贵。
        // 获取当前cToken的供应状态
        CompMarketState storage supplyState = compSupplyState[cToken];
        // 使用率
        uint supplyIndex = supplyState.index;
        // 存款指数
        uint supplierIndex = compSupplierIndex[cToken][supplier];

        // 将供应商的索引更新为当前索引，因为我们正在分配应计 COMP
        // 更新借贷指数(使用率)
        compSupplierIndex[cToken][supplier] = supplyIndex;
        // 贷款指数==0 和 借款指数要大于 1e36
        if (supplierIndex == 0 && supplyIndex >= compInitialIndex) {
            // 涵盖用户在设置市场供应状态指数之前提供代币的情况。
            // 从供应商奖励开始时开始累积的 COMP 奖励用户
            // 为市场设置。
            supplierIndex = compInitialIndex;
        }

        // 计算累积的每个 cToken 的 COMP 累积总和的变化
        Double memory deltaIndex = Double({mantissa: sub_(supplyIndex, supplierIndex)});
        // 获取用户余额
        uint supplierTokens = CToken(cToken).balanceOf(supplier);

        // Calculate COMP accrued: cTokenAmount * accruedPerCToken
        // supplierDelta = cTokenAmount * accruedPerCToken
        // 用户贡献数量 = 用户余额 * 每个计算comp的累积总和
        uint supplierDelta = mul_(supplierTokens, deltaIndex);
        // 当前用户所得comp 数量 = 未体现的 + 用户贡献数量
        uint supplierAccrued = add_(compAccrued[supplier], supplierDelta);
        // 更新用户未体现的COMP 数量
        compAccrued[supplier] = supplierAccrued;

        emit DistributedSupplierComp(CToken(cToken), supplier, supplierDelta, supplyIndex);
    }

    /**
      * @notice 计算借款人应计的 COMP 并可能将其转移给他们
      * @dev 在第一次与协议交互之后，借款人才会开始累积。
      * @param cToken 借款人正在互动的市场
      * @param borrower 将 COMP 分配给借款人的地址
      */
     // 计算借款 当前未产出的COMP。只是更新当前用户的COMP数量，并未发送给用户
    function distributeBorrowerComp(address cToken, address borrower, Exp memory marketBorrowIndex) internal {
        // TODO：如果用户不在借款人市场，则不要分发供应商 COMP。
        // 由于在许多地方调用了 distributeBorrowerComp，此检查应尽可能高效。
        // - 我们真的不想调用外部合约，因为它非常昂贵。
        // 当前cToken的市场借入状态
        CompMarketState storage borrowState = compBorrowState[cToken];
        uint borrowIndex = borrowState.index;
        uint borrowerIndex = compBorrowerIndex[cToken][borrower];

        // Update borrowers's index to the current index since we are distributing accrued COMP
        compBorrowerIndex[cToken][borrower] = borrowIndex;

        if (borrowerIndex == 0 && borrowIndex >= compInitialIndex) {
            // Covers the case where users borrowed tokens before the market's borrow state index was set.
            // Rewards the user with COMP accrued from the start of when borrower rewards were first
            // set for the market.
            borrowerIndex = compInitialIndex;
        }

        // Calculate change in the cumulative sum of the COMP per borrowed unit accrued
        Double memory deltaIndex = Double({mantissa: sub_(borrowIndex, borrowerIndex)});

        uint borrowerAmount = div_(CToken(cToken).borrowBalanceStored(borrower), marketBorrowIndex);
        
        // Calculate COMP accrued: cTokenAmount * accruedPerBorrowedUnit
        uint borrowerDelta = mul_(borrowerAmount, deltaIndex);

        uint borrowerAccrued = add_(compAccrued[borrower], borrowerDelta);
        compAccrued[borrower] = borrowerAccrued;

        emit DistributedBorrowerComp(CToken(cToken), borrower, borrowerDelta, borrowIndex);
    }

    /**
      * @notice 计算自上次应计以来贡献者的额外应计 COMP
      * @param contributor 计算贡献者奖励的地址
      */
    //  更新未获取区块奖励数据。更新用户数据让用户获得最新comp奖励。只修改数据 不提币。
    function updateContributorRewards(address contributor) public {
        // 用户贡献者未得到的comp数量
        // 为什么会出现未获得简历的区块呢？  应为区块一直在增加 用户不能能每个区块都点击一次。
        uint compSpeed = compContributorSpeeds[contributor];
        // console.log("未获得奖励的区块",compSpeed);
        uint blockNumber = getBlockNumber();
        // 获取区块数量 = 区块 - 最后一个奖励的区块
        uint deltaBlocks = sub_(blockNumber, lastContributorBlock[contributor]);
        // console.log("deltaBlocks", deltaBlocks);
        // 区块数量 和 未收到的都大于 0 进去
        if (deltaBlocks > 0 && compSpeed > 0) {
            uint newAccrued = mul_(deltaBlocks, compSpeed);
            uint contributorAccrued = add_(compAccrued[contributor], newAccrued);
            // 更新用户未体现的
            compAccrued[contributor] = contributorAccrued;
            // 最后一个发送过奖励的区块
            lastContributorBlock[contributor] = blockNumber;
        }
    }

    /**
      * @notice 索取持有人在所有市场中应计的所有补偿
      * @param holder 申领 COMP 的地址
      */
    //  领取所有市场 所得到的COMP
    function getComp(address holder) public {
        return claimComp(holder, allMarkets);
    }
    function claimComp(address holder) public {
        return claimComp(holder, allMarkets);
    }

    /**
      * @notice 索取持有人在指定市场累积的所有补偿
      * @param holder 申领 COMP 的地址
      * @param cTokens 申领 COMP 的市场列表
      */
    //  领取指定市场所得到的COMP
    function claimComp(address holder, CToken[] memory cTokens) public {
        address[] memory holders = new address[](1);
        holders[0] = holder;
        claimComp(holders, cTokens, true, true);
    }

    /**
      * @notice 索取持有人应计的所有补偿
      * @param holders 申领 COMP 的地址
      * @param cTokens 申领 COMP 的市场列表
      * @param borrowers 是否索取借贷所得的COMP
      * @param suppliers 是否索取通过供应获得的 COMP
      */
    function claimComp(
        address[] memory holders,   //  领取的地址
        CToken[] memory cTokens,    //  领取的cToken地址
        bool borrowers, //  是否领取借贷COMP奖励
        bool suppliers //  是否领取存款COMP奖励
    ) public {
        for (uint i = 0; i < cTokens.length; i++) {
            CToken cToken = cTokens[i];
            // 是否上市
            require(markets[address(cToken)].isListed, "market must be listed");
            if (borrowers == true) {
                Exp memory borrowIndex = Exp({mantissa: cToken.borrowIndex()});
                // 更新当前用户借款COMP奖励
                updateCompBorrowIndex(address(cToken), borrowIndex);
                for (uint j = 0; j < holders.length; j++) {
                    // 获取借款未产出区块 奖励的COMP
                    distributeBorrowerComp(address(cToken), holders[j], borrowIndex);
                }
            }
            if (suppliers == true) {
                // 更新当前用户存款COMP奖励
                updateCompSupplyIndex(address(cToken));
                for (uint j = 0; j < holders.length; j++) {
                    // 获取存款未产出区块 奖励的COMP
                    distributeSupplierComp(address(cToken), holders[j]);
                }
            }
        }
        for (uint j = 0; j < holders.length; j++) {
            // 将未获取的COMP全部发送给调用者
            compAccrued[holders[j]] = grantCompInternal(holders[j], compAccrued[holders[j]]);
            console.log(compAccrued[holders[j]]);
        }
    }

    /**
      * @notice 将 COMP 转移给用户
      * @dev 注意：如果没有足够的 COMP，我们不会执行全部传输。
      * @param user 将COMP转入的用户地址
      * @param amount 要（可能）转移的 COMP 数量
      * @return 未转移给用户的 COMP 数量
      */
    //  将所有市场中的COMP发送给用户
    function grantCompInternal(address user, uint amount) internal returns (uint) {
        // 循环所有市场
        // for (uint i = 0; i < allMarkets.length; ++i) {
        //     address market = address(allMarkets[i]);
        //     // 返回 每个区块产生COMP的借款速度
        //     bool noOriginalSpeed = compBorrowSpeeds[market] == 0;
        //     // 返回 供应商存款指数
        //     bool invalidSupply = noOriginalSpeed && compSupplierIndex[market][user] > 0;
        //     // 返回 供应商借款指数
        //     bool invalidBorrow = noOriginalSpeed && compBorrowerIndex[market][user] > 0;
        //     console.log(noOriginalSpeed,invalidSupply,invalidBorrow,amount);
        //     // 如果有一个存在那么久返回对应输入的值。
        //     if (invalidSupply || invalidBorrow) {
        //         // console.log("amount",amount);
        //         return amount;
        //     }
        // }
        // 获取COMP奖励的地址
        Comp comp = Comp(comAddress);
        // 查询当前合约的COMP余额
        uint compRemaining = comp.balanceOf(address(this));
        // 输入有值，输入的值 要小于当前合约的余额
            console.log(amount,compRemaining,address(comp),address(this) );
        if (amount > 0 && amount <= compRemaining) {
            // 给调用者转帐
            comp.transfer(user, amount);
            return 0;
        }
        // console.log(amount);
        // 返回发送的额度
        return amount;
    }

    /*** Comp Distribution Admin ***/

    /**
      * @notice 将 COMP 转移给接收者
      * @dev 注意：如果没有足够的 COMP，我们不会执行全部传输。
      * @param recipient 将 COMP 转入的收件人地址
      * @param amount 要（可能）转移的 COMP 数量
      */
    //  将comp转移给接收者
    function _grantComp(address recipient, uint amount) public {
        require(adminOrInitializing(), "only admin can grant comp");
        uint amountLeft = grantCompInternal(recipient, amount);
        require(amountLeft == 0, "insufficient comp for grant");
        emit CompGranted(recipient, amount);
    }

    /**
      * @notice 为指定市场设置 COMP 借入和供应速度。
      * @param cTokens COMP 更新速度的市场。
      * @param supplySpeeds 相应市场的存款 COMP 速度。
      * @param borrowSpeeds 相应市场的借款 COMP 速度。
      */
    //  设置挖款COMP供应速率
    // 开启挖矿奖励
    // 速率是 每个区块的COMP（单位：wei）
    function _setCompSpeeds(
        CToken[] memory cTokens,    //  开启挖款奖励的cToken
        uint[] memory supplySpeeds,     //  存款 挖款速率 单位wei
        uint[] memory borrowSpeeds      //  借款 挖款速率 单位wei
    ) public {
        require(adminOrInitializing(), "only admin can set comp speed");

        uint numTokens = cTokens.length;
        require(numTokens == supplySpeeds.length && numTokens == borrowSpeeds.length, "Comptroller::_setCompSpeeds invalid input");

        for (uint i = 0; i < numTokens; ++i) {
            setCompSpeedInternal(cTokens[i], supplySpeeds[i], borrowSpeeds[i]);
        }
    }

    /**
      * @notice 为单个贡献者设置 COMP 速度
      * @param contributor 其 COMP 更新速度的贡献者
      * @param compSpeed 贡献者的新 COMP 速度
      */
    //  单独设置某个人的挖款速率 
    function _setContributorCompSpeed(address contributor, uint compSpeed) public {
        require(adminOrInitializing(), "only admin can set comp speed");

        // 请注意，COMP 速度可以设置为 0 以停止对贡献者的流动性奖励
        // 更新未获取区块奖励
        updateContributorRewards(contributor);
        if (compSpeed == 0) {
            // release storage
            // 清空 简历的最后一个区块
            delete lastContributorBlock[contributor];
        } else {
            // 设置 奖励的最后一个区块
            lastContributorBlock[contributor] = getBlockNumber();
        }
        // 贡献者的挖款速率
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

    // 手动更新存款未提COMP
    function updateCompSupply(address cToken,address account) public {
        updateCompSupplyIndex(cToken);
        distributeSupplierComp(cToken, account);
    }
    // 手动更新借款未提COMP
    function updateCompBorrow(address cToken,address account) public {
        Exp memory borrowIndex = Exp({mantissa: CToken(cToken).borrowIndex()});
        updateCompBorrowIndex(cToken, borrowIndex);
        distributeBorrowerComp(cToken, account, borrowIndex);
    }
    
    /**
      * @notice 如果给定的 cToken 市场已被弃用，则返回 true
      * @dev 已弃用的 cToken 市场中的所有借款都可以立即清算
      * @param cToken 检查是否弃用的市场
      */
    //  检查cToken是否被市场弃用
    function isDeprecated(CToken cToken) public view returns (bool) {
        return
            markets[address(cToken)].collateralFactorMantissa == 0 && 
            borrowGuardianPaused[address(cToken)] == true && 
            cToken.reserveFactorMantissa() == 1e18
        ;
    }

    function getBlockNumber() public view returns (uint) {
        return block.number;
    }

    /**
     * @notice Return the address of the COMP token
     * @return The address of COMP
     */
    function getCompAddress() public view returns (address) {
        return comAddress;
        // return /**start*/0x5FbDB2315678afecb367f032d93F642f64180aa3/**end*/;
    }
    function setCompAddress(address _compAddress) external {
        comAddress = _compAddress;
    }
}
