pragma solidity ^0.5.16;

import "./CToken.sol";
import "./PriceOracle.sol";

contract UnitrollerAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of Unitroller
    */
   //   代理到那个合约来执行
    address public comptrollerImplementation;

    /**
    * @notice Pending brains of Unitroller
    */
    address public pendingComptrollerImplementation;
}

// 价格预言机
contract ComptrollerV1Storage is UnitrollerAdminStorage {

    /**
     * @notice Oracle which gives the price of any given asset
     */
    PriceOracle public oracle;

    /**
     * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
     */
    // 债务超过资产抵押率的时候可以清算多少债务
    // 50%
    uint public closeFactorMantissa;

    /**
     * @notice Multiplier representing the discount on collateral that a liquidator receives
     */
    // 清算者在清算的时候可以多得到的奖励
    // 1.08
    uint public liquidationIncentiveMantissa;

    /**
     * @notice Max number of assets a single account can participate in (borrow or use as collateral)
     */
    // 最多有多少资产
    // 20
    uint public maxAssets;

    /**
     * @notice Per-account mapping of "assets you are in", capped by maxAssets
     */
    // 记录用户参与的资产，不区分存款和借款
    mapping(address => CToken[]) public accountAssets;

}

contract ComptrollerV2Storage is ComptrollerV1Storage {
    struct Market {
        /// @notice Whether or not this market is listed
        // 资产是否上市
        bool isListed;

        /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
         */
        // 抵押率
        // 100usdc 可以抵押价值90usdc的资产
        uint collateralFactorMantissa;

        /// @notice Per-market mapping of "accounts in this asset"
        // 用户是否进入资产？
        mapping(address => bool) accountMembership;

        /// @notice Whether or not this market receives COMP
        bool isComped;
    }

    /**
     * @notice Official mapping of cTokens -> Market metadata
     * @dev Used e.g. to determine if a market is supported
     */
    // 每个资产对应的配置
    mapping(address => Market) public markets;


    /**
    *@notice Pause Guardian 可以暂停某些操作作为安全机制。
    *允许用户删除自己的资产的操作不能暂停。
    *清算/扣押/转移只能在全球范围内暂停，不能按市场暂停。
    */
    address public pauseGuardian;
    // 不能存款
    bool public _mintGuardianPaused;
    // 不能借款
    bool public _borrowGuardianPaused;
    // 是否开启转账功能
    bool public transferGuardianPaused;
    bool public seizeGuardianPaused;
    // 对应资产的开关
    mapping(address => bool) public mintGuardianPaused;
    mapping(address => bool) public borrowGuardianPaused;
}
// v3-v6 自己的代币相关
contract ComptrollerV3Storage is ComptrollerV2Storage {
    // 市场状态
    struct CompMarketState {
        /// @notice The market's last updated compBorrowIndex or compSupplyIndex
        // 下标
        uint224 index;

        /// @notice The block number the index was last updated at
        // 区块
        uint32 block;
    }

    /// @notice A list of all markets
    CToken[] public allMarkets;

    /// @notice The rate at which the flywheel distributes COMP, per block
    uint public compRate;

    /// @notice The portion of compRate that each market currently receives
    // 每个市场当前收到的compRate份额
    mapping(address => uint) public compSpeeds;

    /// @notice The COMP market supply state for each market
    // 每个市场的COMP市场供应状态
    mapping(address => CompMarketState) public compSupplyState;

    /// @notice The COMP market borrow state for each market
    mapping(address => CompMarketState) public compBorrowState;

    /// @notice The COMP borrow index for each market for each supplier as of the last time they accrued COMP
    // 截至最后一次计算COMP时，每个供应商的每个市场的COMP借贷指数
    mapping(address => mapping(address => uint)) public compSupplierIndex;

    /// @notice The COMP borrow index for each market for each borrower as of the last time they accrued COMP
    // 🧍各市场下，每个用户地址的指数
    mapping(address => mapping(address => uint)) public compBorrowerIndex;

    /// @notice The COMP accrued but not yet transferred to each user
    // 每个用户未提现的COPM
    mapping(address => uint) public compAccrued;
}

contract ComptrollerV4Storage is ComptrollerV3Storage {
    /// @notice The borrowCapGuardian can set borrowCaps to any number for any market. Lowering the borrow cap could disable borrowing on the given market.
    address public borrowCapGuardian;

    /// @notice Borrow caps enforced by borrowAllowed for each cToken address. Defaults to zero which corresponds to unlimited borrowing.
    mapping(address => uint) public borrowCaps;
}

contract ComptrollerV5Storage is ComptrollerV4Storage {
    /// @notice The portion of COMP that each contributor receives per block
    mapping(address => uint) public compContributorSpeeds;

    /// @notice Last block at which a contributor's COMP rewards have been allocated
    mapping(address => uint) public lastContributorBlock;
}

contract ComptrollerV6Storage is ComptrollerV5Storage {
    /// @notice The rate at which comp is distributed to the corresponding borrow market (per block)
    mapping(address => uint) public compBorrowSpeeds;

    /// @notice The rate at which comp is distributed to the corresponding supply market (per block)
    mapping(address => uint) public compSupplySpeeds;
}
