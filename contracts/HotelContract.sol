pragma solidity ^0.8.28;
import "@openzeppelin/contracts/access/Ownable.sol";

contract HotelContract is Ownable {
    constructor(address owner, address _managementAddress) Ownable(owner) {
        managementAddress = _managementAddress;
    }

    address managementAddress;

    struct Room {
        address roomAddress; // 对应的 HouseToken 合约地址
        string descriptionURL; // 房间描述的URL
        string imagesURL; // 房间图片的URL
        uint256 price; // 每晚的价格
        uint256 next30daysBooking; // 未来30天的可用性（0 表示可用，1 表示已预订）
        uint256 lastBookingUpdate; // 上次预订信息更新时间戳
        bool isAvailable; // 是否可预订
    }

    uint256 roomCount = 0;
    Room[] rooms;

    event roomListed(uint256 roomId);
    event roomUpdated(uint256 roomId, string _descriptionURL, string _imagesURL, uint256 _price);
    event roomUnlisted(uint256 roomId);

    function getRooms() external view returns (Room[] memory) {
        return rooms;
    }

    function listRoom(
        address _roomAddress,
        string memory _descriptionURL,
        string memory _imagesURL,
        uint256 _price
    ) external onlyOwner{
        rooms[roomCount] = Room({
            roomAddress: _roomAddress,
            descriptionURL: _descriptionURL,
            imagesURL: _imagesURL,
            price: _price,
            next30daysBooking: 0,
            lastBookingUpdate: block.timestamp,
            isAvailable: true
        });
        roomCount++;
    }

    function updateRoom(
        uint256 roomId,
        string memory _descriptionURL,
        string memory _imagesURL,
        uint256 _price,
        uint256 _next30daysBooking
    ) external onlyOwner{
        // 确保房间存在
        require(roomId > 0 && roomId <= roomCount, "Room does not exist");
        Room storage room = rooms[roomId];
        // 更新房间信息
        room.descriptionURL = _descriptionURL;
        room.imagesURL = _imagesURL;
        room.price = _price;
        room.next30daysBooking = _next30daysBooking;
        room.lastBookingUpdate = block.timestamp; // 更新修改时间
        emit roomUpdated(roomId, _descriptionURL, _imagesURL, _price);
    }

    function unlistRoom(uint256 roomId) external onlyOwner{
        // 确保房间存在
        require(roomId > 0 && roomId <= roomCount, "Room does not exist");
        Room storage room = rooms[roomId];
        // 下架房间
        room.isAvailable = false;
        emit roomUnlisted(roomId);
    }
}
