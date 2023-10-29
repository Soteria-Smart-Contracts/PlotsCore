// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

contract PlotsCore{
    //Variable and pointer Declarations
    address public Treasury;
    address public LendContract;
    address[] public ListedCollections;

    enum ListingType{
        Ownership,
        Usage
    }
    
    struct Listing{
        address Collection;
        uint256 TokenId;
        uint256 Value;
        ListingType OwnershipOption;
    }

    mapping(address => bool) public Admins;
    modifier OnlyAdmin(){
        require(Admins[msg.sender], "Only Admin");
        _;
    }

    mapping(address => uint256[]) public AvailableTokensByCollection;
    mapping(address => mapping(uint256 => uint256)) public AvailableTokensByCollectionIndex;
    mapping(address => uint256) public ListedCollectionsIndex;
    mapping(address => mapping(address => uint256)) public OwnershipByPurchase;
    //Listings mapping is a mapping of the token ID and the nft contract address to the listing struct
    mapping(address => mapping(uint256 => Listing)) public Listings;
    

    constructor(address [] memory _admins){
        Treasury = address(new PlotsTreasury(address(this)));
        for(uint256 i = 0; i < _admins.length; i++){
            Admins[_admins[i]] = true;
        }
    }

    //Public Functions



    function ListTokenForUsage(address Collection, uint256 TokenId, uint256 Value) public{
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(AvailableTokensByCollectionIndex[Collection][TokenId] == 0, "Token already listed");
        require(ERC721(Collection).ownerOf(TokenId) == Treasury, "Token not owned by treasury");
        require(condition);

        //setup listing

        Listings[Collection][TokenId] = Listing(Collection, TokenId, Value, ListingType.Usage);

        AvailableTokensByCollection[Collection].push(TokenId);
        AvailableTokensByCollectionIndex[Collection][TokenId] = AvailableTokensByCollection[Collection].length - 1;
    }


    //Public View Functions

    function GetAvailableTokensByCollection(address _collection) public view returns(uint256[] memory){
        return AvailableTokensByCollection[_collection];
    }

    function GetListedCollections() public view returns(address[] memory){
        return ListedCollections;
    }

    function GetSingularListing(address _collection, uint256 _tokenId) public view returns(Listing memory){
        return Listings[_collection][_tokenId];
    }

    function GetListedCollection(address _collection) public view returns(Listing[] memory){
        Listing[] memory _listings = new Listing[](AvailableTokensByCollection[_collection].length);
        for(uint256 i = 0; i < AvailableTokensByCollection[_collection].length; i++){
            _listings[i] = Listings[_collection][AvailableTokensByCollection[_collection][i]];
        }
        return _listings;
    }

    //Only Admin Functions

    function ListTokenForOwnership(address Collection, uint256 TokenId, uint256 Value) public OnlyAdmin{
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(AvailableTokensByCollectionIndex[Collection][TokenId] == 0, "Token already listed");
        require(ERC721(Collection).ownerOf(TokenId) == Treasury, "Token not owned by treasury");

        AvailableTokensByCollection[Collection].push(TokenId);
        AvailableTokensByCollectionIndex[Collection][TokenId] = AvailableTokensByCollection[Collection].length - 1;
    }


    function AddCollection(address _collection) public OnlyAdmin{
        ListedCollections.push(_collection);
        ListedCollectionsIndex[_collection] = ListedCollections.length - 1;
    }

    function RemoveCollection(address _collection) public OnlyAdmin{
        uint256 index = ListedCollectionsIndex[_collection];
        ListedCollections[index] = ListedCollections[ListedCollections.length - 1];
        ListedCollectionsIndex[ListedCollections[index]] = index;
        ListedCollections.pop();
    }
}

contract PlotsTreasury{
    //Variable and pointer Declarations
    address public PlotsCore;

    constructor(address Core){
        PlotsCore = Core;
    }
}

contract PlotsLend{
    //Variable and pointer Declarations
    address public PlotsCore;

    constructor(address Core){
        PlotsCore = Core;
    }

    
}



interface ERC721 {
    function balanceOf(address _owner) external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external payable;
    function transferFrom(address _from, address _to, uint256 _tokenId) external payable;
    function approve(address _approved, uint256 _tokenId) external payable;
    function setApprovalForAll(address _operator, bool _approved) external;
    function getApproved(uint256 _tokenId) external view returns (address);
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);
}
