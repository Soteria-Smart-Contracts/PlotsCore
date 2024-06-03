console.log('merklegen.js loaded');


          await ethereum.request({ method: 'eth_requestAccounts' });
          window.web3 = await new Web3(ethereum);
          await getID();
          if (netID != 61){ //Change and fix
              console.log("The current Metamask/Web3 network is not Ethereum Classic, please connect to Ethereum Classic."); 
              alert("The current Metamask/Web3 network is not Ethereum Classic, please connect to the Ethereum Classic network.");
              return("Failed to connect")
          }
          accountarray = await web3.eth.getAccounts();
          DAOcore = new window.web3.eth.Contract(window.CoreABI, CoreAddress);
          DAOvoting = new window.web3.eth.Contract(window.VotingABI, VotingAddress);
          CLDtoken = new window.web3.eth.Contract(window.CLDABI, CLDaddress);
          account = accountarray[0];
          console.log('Logged In')
          LoggedIn = true;
          await GetHENS();
          await RemoveOverlay();

          localStorage.setItem("ClassicDAOLogin", "true");
          
          return(true)
      } 
      else { 
          alert("No ETHER Wallet available")
      }
  }
}

//convert the whitelistAddresses to an array of addresses with the points number appended to the address end
let WhitelistAddresses = data2.map((address) => {
  return address.address;
});

let ClaimantAddresses = data1.map((address) => {
  return address.address + address.points;
});

WhitelistAddresses = WhitelistAddresses.concat(ClaimantAddresses);

console.log(WhitelistAddresses);

const leafNodesWhitelist = WhitelistAddresses.map(addr => keccak256(addr));
let WhitelistMerkleTree = new MerkleTree(leafNodesWhitelist, keccak256, { sortPairs: true });

// Get the Merkle Root of the Merkle Tree
const rootHashWhitelist = WhitelistMerkleTree.getRoot();
const rootHashWhitelistBytes32 = '0x' + WhitelistMerkleTree.getRoot().toString('hex');
console.log("Root Hash Whitelist: ", rootHashWhitelistBytes32);

// Function to generate hex proof for a claiming address
function GenerateHexProofWhitelist(claimingAddress) {
  claimingAddress = keccak256(claimingAddress);
  const hexProof = WhitelistMerkleTree.getHexProof(claimingAddress);
  const isAddressInTree = WhitelistMerkleTree.verify(hexProof, claimingAddress, rootHashWhitelist);
  //get the lea

  return {
    hexProof: hexProof,
    isAddressInTree: isAddressInTree
  };
}
