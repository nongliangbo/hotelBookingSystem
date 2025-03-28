// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract HouseToken is ERC20 {
    address public management; //记录创建的平台
    string public description; //TODO 改为hash
    uint256 public dividendsPerShare; //每股分红
    mapping(address => uint256) public dividendCreditedTo;
    
    event RevenueReceived(uint256 amount, uint256 newDividendsPerShare);
    event DividendsWithdrawn(address indexed user, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        string memory _description,
        uint256 _totalShares,
        address _management
    ) ERC20(_name, _symbol) {
        description = _description;
        management = _management;
        _mint(_management, _totalShares);
    }

    function decimals() public view virtual override returns (uint8) {
        return 0; // 无小数份额
    }

    //分红更新
    function receiveRevenue(uint256 amount) external {
        require(msg.sender == management, "Only management can call this");
        if (totalSupply() > 0) {
            dividendsPerShare += amount / totalSupply();
        }
        emit RevenueReceived(amount, dividendsPerShare);
    }


    //由用户自提分红
    function withdrawDividends() external {

/*      作用是让用户收到转让的token之后，初始化token的分红。但是会误判到没有提取过分红的用户
        uint256 credited = dividendCreditedTo[msg.sender];
        if (credited == 0) {
            credited = dividendsPerShare; // 初始化，避免计算错误
        }
*/
        uint256 dividends = (dividendsPerShare - dividendCreditedTo[msg.sender]) * balanceOf(msg.sender);
        require(dividends > 0, "No dividends to withdraw");
        
        //先记账再转账
        dividendCreditedTo[msg.sender] = dividendsPerShare;
        (bool success, ) = msg.sender.call{value: dividends}("");
        require(success, "Dividend transfer failed");
        
        emit DividendsWithdrawn(msg.sender, dividends);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(amount > 0, "transfer amount must > 0");
        require(balanceOf(msg.sender) >= amount, "Not enough Token");
        // 在转让份额前先结算原本所有者的分红
        if (dividendCreditedTo[msg.sender] < dividendsPerShare) {
            uint256 dividends = (dividendsPerShare - dividendCreditedTo[msg.sender]) * balanceOf(msg.sender);
            //dividendCreditedTo[msg.sender] = dividendsPerShare;
            if (dividends > 0) {
                dividendCreditedTo[msg.sender] = dividendsPerShare;
                //从合约转账给msg.sender，金额是dividends
                (bool success, ) = msg.sender.call{value: dividends}("");
                require(success, "Dividend transfer failed");
                emit DividendsWithdrawn(msg.sender, dividends);
            }
        }
        // 在转让前，把B的分红也结算掉。结算的手续费由A付
        if(dividendCreditedTo[to] < dividendsPerShare){
            uint256 dividendsTo = (dividendsPerShare - dividendCreditedTo[to]) * balanceOf(to);
            dividendCreditedTo[to] = dividendsPerShare;
            if (dividendsTo > 0) {
                //从合约转账给to(B)，金额是dividends
                (bool success, ) = to.call{value: dividendsTo}("");
                require(success, "Dividend transfer failed");
                emit DividendsWithdrawn(to, dividendsTo);
            }            
        }
        
        return super.transfer(to, amount);
    }

    // 允许合约接收ETH
    receive() external payable {}
}