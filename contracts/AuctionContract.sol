// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AuctionContract {
    struct Auction {
        //拍卖发起人地址,出售人地址
        address seller;
        //拍卖的房屋代币合约地址
        address houseToken;
        //拍卖的代币分割数量
        uint256 tokenAmount;
        //最低出价
        uint256 minBid;
        //当前最高出价
        uint256 currentHighestBid;
        //当前最高出价用户地址
        address currentHighestBidder;
        //拍卖截止日期
        uint32 endTime;
        bool started;
        bool finalized; //结算,并完全结束合约
    }

    //创建拍卖事件
    event AuctionCreated(
        uint256 auctionId,
        address seller,
        address houseToken,
        uint256 tokenAmount,
        uint256 minBid,
        uint32 endTime
    );
    //竞拍事件
    event BidPlaced(uint256 auctionId, address bidder, uint256 bidAmount);
    //结算事件
    event AuctionFinalized(uint256 auctionId);
    //退回金额事件
    event Withdraw(uint256 auctionId, address bidder, uint256 refundAmount);

    //已发起的拍卖总数
    uint256 public auctionCount;

    //可以有多个拍卖
    mapping(uint256 => Auction) public auctions;

    //单独存储每个拍卖的出价映射
    //某次拍卖的，某个用户的出价
    mapping(uint256 => mapping(address => uint256)) public bids;

    function startAuction(
        address _houseToken,
        uint256 _tokenAmount,
        uint256 _minBid,
        uint256 _duration
    ) public {
        // require(msg.sender == seller, "Only the seller can start the auction.");
        // require(!started, "has been started");

        require(_duration > 0, "Auction duration must be greater than 0.");
        require(_minBid > 0, "Minimum bid must be greater than 0.");
        require(
            ERC20(_houseToken).balanceOf(msg.sender) >= _tokenAmount,
            "Insufficient balance."
        );

        //收取卖家的代币
        ERC20(_houseToken).transferFrom(
            msg.sender,
            address(this),
            _tokenAmount
        );

        uint256 auctionId = auctionCount++;
        uint32 _endTime = uint32(block.timestamp + _duration);

        auctions[auctionId] = Auction({
            seller: msg.sender,
            houseToken: _houseToken,
            tokenAmount: _tokenAmount,
            minBid: _minBid,
            currentHighestBid: 0,
            currentHighestBidder: address(0),
            endTime: _endTime,
            started: true,
            finalized: false
        });

        emit AuctionCreated(
            auctionId,
            msg.sender,
            _houseToken,
            _tokenAmount,
            _minBid,
            _endTime
        );
    }

    //2. placeBid（竞拍）
    function placeBid(uint256 auctionId) public payable {
        Auction storage auction = auctions[auctionId];
        require(auction.started, "Auction not started.");
        require(!auction.finalized, "Auction has ended.");
        require(msg.value >= auction.minBid, "Bid below minimum bid.");
        require(block.timestamp < auction.endTime, "Auction has expired.");

        //当前拍卖价格
        uint256 currentBid = bids[auctionId][msg.sender] + msg.value;
        bids[auctionId][msg.sender] = currentBid;

        //如果当前出价大于最高出价，则更新最高出价和最高出价用户地址
        if (currentBid > auction.currentHighestBid) {
            auction.currentHighestBid = currentBid;
            auction.currentHighestBidder = msg.sender;
        }

        emit BidPlaced(auctionId, msg.sender, currentBid);
    }

    //3. finalizeAuction（拍卖结算）
    function finalizeAuction(uint256 auctionId) public payable{
        Auction storage auction = auctions[auctionId];
        //当前时间必须大于结束时间
        require(auction.endTime < block.timestamp, "Auction has not ended.");

        require(!auction.finalized, "Auction has already been finalized.");

        if (auction.currentHighestBidder != address(0)) {
            //把当前合约的拍卖款转给拍卖人
            payable(auction.seller).transfer(auction.currentHighestBid);

            //把拍下的代币转给买家
            ERC20(auction.houseToken).transferFrom(
                auction.seller, //卖家 from
                auction.currentHighestBidder, //买家 to
                auction.tokenAmount //币的金额
            );
        }

        auction.finalized = true;
        emit AuctionFinalized(auctionId);
    }

    //4. withdraw（提取拍卖退款）
    function withdraw(uint256 auctionId) public  payable{
        Auction storage auction = auctions[auctionId];
        require(auction.finalized, "Auction has not been finalized yet.");
        require(bids[auctionId][msg.sender] > 0, "No bid to withdraw.");

        uint256 refundAmount = bids[auctionId][msg.sender];
        bids[auctionId][msg.sender] = 0;

        payable(msg.sender).transfer(refundAmount);
    }



    function endAuction(uint256 auctionId) public payable {
        //结束拍卖
        Auction storage auction = auctions[auctionId];
        require(
            auction.currentHighestBidder != address(0),
            "No bids placed yet."
        );

        if (auction.currentHighestBidder != address(0)) {
            //把当前合约的拍卖款转给拍卖人
            payable(auction.seller).transfer(auction.currentHighestBid);

            //把拍下的代币转给买家
            ERC20(auction.houseToken).transferFrom(
                auction.seller, //卖家 from
                auction.currentHighestBidder, //买家 to
                auction.tokenAmount //币的金额
            );
        }

        auction.finalized = true;
        emit AuctionFinalized(auctionId);
    }
}
