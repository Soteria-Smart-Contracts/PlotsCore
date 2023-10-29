// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

contract PlotsCore{
    //Variable and pointer Declarations
    address public Treasury;
    address public LendContract;
    address[] public ListedCollections;



    mapping(address => bool) public Admins;
    modifier OnlyAdmin(){
        require(Admins[msg.sender], "Only Admin");
        _;
    }

    mapping(address => uint256[]) public AvailableTokensByCollection;
    mapping(address => mapping(uint256 => uint256)) public AvailableTokensByCollectionIndex;
    mapping(address => uint256) public ListedCollectionsIndex;

    

    constructor(address [] memory _admins){
        Treasury = address(new PlotsTreasury(address(this)));
        for(uint256 i = 0; i < _admins.length; i++){
            Admins[_admins[i]] = true;
        }
    }

    //Public Functions





    function GetAvailableTokensByCollection(address _collection) public view returns(uint256[] memory){
        return AvailableTokensByCollection[_collection];
    }


    //Only Admin Functions

    function ListToken(address Collection, uint256 TokenId, uint256 Value) public OnlyAdmin{
        require(ListedCollectionsIndex[Collection] != 0, "Collection not listed");
        require(AvailableTokensByCollectionIndex[Collection][TokenId] == 0, "Token already listed");
        //require that the treasury or lend contract has the token
        require();

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
