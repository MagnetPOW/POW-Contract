//0xe58d55786ff7a109de4d82305dc5b081b6ac1ca6
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract MiningContract is Ownable, ReentrancyGuard {
    // 挖矿任务结构
    struct MiningTask {
        uint256 nonce; // 任务随机数
        uint256 difficulty; // 挖矿难度
        bool active; // 任务是否有效
    }

    // 白名单级别
    enum WhitelistLevel { None, Level30, Level200, Level1000 }

    // 白名单映射
    mapping(address => bool) public whitelist30; // 30 USDT
    mapping(address => bool) public whitelist200; // 200 USDT
    mapping(address => bool) public whitelist1000; // 1000 USDT

    // 用户当前挖矿任务，private 隐藏
    mapping(address => MiningTask) private userTasks;

    // 奖励金额（以 Wei 为单位）
    uint256 public constant FREE_REWARD = 0.3 ether;
    uint256 public constant LEVEL30_REWARD = 7 ether;
    uint256 public constant LEVEL200_REWARD = 120 ether;
    uint256 public constant LEVEL1000_REWARD = 1000 ether;

    // 事件
    event NewMiningTask(address indexed user, uint256 difficulty); // 移除 nonce，防止泄露
    event MiningReward(address indexed user, uint256 reward);
    event WhitelistUpdated(address indexed user, WhitelistLevel level);

    // 构造函数，设置合约拥有者
    constructor() Ownable(msg.sender) {}

    // 接收 Ether 用于奖励
    receive() external payable {}

    // 获取用户白名单级别
    function getWhitelistLevel(address user) public view returns (WhitelistLevel) {
        if (whitelist1000[user]) return WhitelistLevel.Level1000;
        if (whitelist200[user]) return WhitelistLevel.Level200;
        if (whitelist30[user]) return WhitelistLevel.Level30;
        return WhitelistLevel.None;
    }

    // 管理员添加用户到白名单
    function addToWhitelist(address user, WhitelistLevel level) external onlyOwner {
        // 移除用户从其他白名单
        whitelist30[user] = false;
        whitelist200[user] = false;
        whitelist1000[user] = false;

        // 添加到指定白名单
        if (level == WhitelistLevel.Level30) whitelist30[user] = true;
        else if (level == WhitelistLevel.Level200) whitelist200[user] = true;
        else if (level == WhitelistLevel.Level1000) whitelist1000[user] = true;

        emit WhitelistUpdated(user, level);
    }

    // 管理员移除用户从白名单
    function removeFromWhitelist(address user) external onlyOwner {
        whitelist30[user] = false;
        whitelist200[user] = false;
        whitelist1000[user] = false;
        emit WhitelistUpdated(user, WhitelistLevel.None);
    }

    // 用户请求新的挖矿任务
    function requestMiningTask() external {
        // 改进 nonce 生成，结合 block.prevrandao 增加随机性
        uint256 nonce = uint256(keccak256(abi.encodePacked(
            block.prevrandao,
            msg.sender,
            block.number,
            block.timestamp
        )));
        // 设置难度（可根据实际需求调整）
        uint256 difficulty = 2 ** 240; // 要求哈希前 16 位为 0

        // 保存用户任务
        userTasks[msg.sender] = MiningTask(nonce, difficulty, true);
        emit NewMiningTask(msg.sender, difficulty); // 只记录 difficulty
    }

    // 用户提交挖矿结果
    function submitMiningResult(uint256 solution) external nonReentrant {
        MiningTask memory task = userTasks[msg.sender];
        require(task.active, "No active mining task");
        require(address(this).balance >= LEVEL1000_REWARD, "Insufficient contract balance");
        require(task.difficulty > 0, "Invalid difficulty"); // 防止除零

        // 验证哈希是否满足难度要求
        bytes32 hash = keccak256(abi.encodePacked(task.nonce, msg.sender, solution));
        // 使用乘法替代除法，避免大整数运算
        require(uint256(hash) <= type(uint256).max / task.difficulty, "Invalid hash");

        // 发放奖励
        uint256 reward;
        WhitelistLevel level = getWhitelistLevel(msg.sender);
        if (level == WhitelistLevel.Level1000) reward = LEVEL1000_REWARD;
        else if (level == WhitelistLevel.Level200) reward = LEVEL200_REWARD;
        else if (level == WhitelistLevel.Level30) reward = LEVEL30_REWARD;
        else reward = FREE_REWARD;

        // 确保余额足够
        require(address(this).balance >= reward, "Not enough balance for reward");

        // 标记任务完成
        userTasks[msg.sender].active = false;

        // 发放奖励
        (bool success, ) = payable(msg.sender).call{value: reward}("");
        require(success, "Reward transfer failed");

        emit MiningReward(msg.sender, reward);
    }

    // 用户查看自己的挖矿任务
    function getMyTask() external view returns (uint256 nonce, uint256 difficulty, bool active) {
        require(userTasks[msg.sender].active, "No active mining task");
        MiningTask memory task = userTasks[msg.sender];
        return (task.nonce, task.difficulty, task.active);
    }

    // 查看合约余额
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    // 管理员提取剩余 Ether（仅限紧急情况）
    function withdrawEther(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient balance");
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, "Withdrawal failed");
    }
}