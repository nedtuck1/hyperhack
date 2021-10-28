import IHyperverseComposable from "../Hyperverse/IHyperverseComposable.cdc"
import IHyperverseModule from "../Hyperverse/IHyperverseModule.cdc"
import HyperverseModule from "../Hyperverse/HyperverseModule.cdc"
import SimpleNFT from "./SimpleNFT.cdc"
import SimpleFT from "./SimpleFT.cdc"

pub contract NFTMarketplace: IHyperverseModule, IHyperverseComposable {

    /**************************************** METADATA ****************************************/

    access(contract) let metadata: HyperverseModule.ModuleMetadata
    pub fun getMetadata(): HyperverseModule.ModuleMetadata {
        return self.metadata
    }

    /**************************************** TENANT ****************************************/

    pub event TenantCreated(id: String)
    pub event TenantReused(id: String)
    access(contract) var clientTenants: {Address: [String]}
    pub fun getClientTenants(account: Address): [String] {
        return self.clientTenants[account]!
    }
    access(contract) var tenants: @{String: Tenant{IHyperverseComposable.ITenant, IState}}
    pub fun getTenant(id: String): &Tenant{IHyperverseComposable.ITenant, IState} {
        return &self.tenants[id] as &Tenant{IHyperverseComposable.ITenant, IState}
    }
    access(contract) var aliases: {String: String}
    access(contract) fun addAlias(original: String, new: String) {
        pre {
            self.tenants[original] != nil: "Original tenantID does not exist."
        }
        self.aliases[new] = original
    }


    pub resource interface IState {
        pub let tenantID: String
        pub var holder: Address
    }
    
    pub resource Tenant: IHyperverseComposable.ITenant, IState {
        pub let tenantID: String
        pub var holder: Address

        init(_tenantID: String, _holder: Address) {
            self.tenantID = _tenantID
            self.holder = _holder
        }
    }

    /**************************************** PACKAGE ****************************************/

    pub let PackageStoragePath: StoragePath
    pub let PackagePrivatePath: PrivatePath
    pub let PackagePublicPath: PublicPath
   
    pub resource interface PackagePublic {
       pub fun SimpleNFTPackagePublic(): &SimpleNFT.Package{SimpleNFT.PackagePublic}
       pub fun SimpleFTPackagePublic(): &SimpleFT.Package{SimpleFT.PackagePublic}
       pub fun borrowSaleCollectionPublic(tenantID: String): &SaleCollection{SalePublic}
    }
    
    pub resource Package: PackagePublic {
        pub let SimpleNFTPackage: Capability<&SimpleNFT.Package>
        pub fun SimpleNFTPackagePublic(): &SimpleNFT.Package{SimpleNFT.PackagePublic} {
            return self.SimpleNFTPackage.borrow()! as &SimpleNFT.Package{SimpleNFT.PackagePublic}
        }
        pub let SimpleFTPackage: Capability<&SimpleFT.Package>
        pub fun SimpleFTPackagePublic(): &SimpleFT.Package{SimpleFT.PackagePublic} {
            return self.SimpleFTPackage.borrow()! as &SimpleFT.Package{SimpleFT.PackagePublic}
        }

        pub var salecollections: @{String: SaleCollection}

        pub fun instance(tenantIDs: {String: UInt64}) {
            var tenantID: String = self.owner!.address.toString().concat(".").concat(tenantIDs["NFTMarketplace"]!.toString())
            
            /* Dependencies */
            if tenantIDs["SimpleFT"] == nil {
                self.SimpleFTPackage.borrow()!.instance(tenantIDs: {"SimpleFT": tenantIDs["NFTMarketplace"]!})
            } else {
                self.SimpleFTPackage.borrow()!.addAlias(original: tenantIDs["SimpleFT"]!, new: tenantIDs["NFTMarketplace"]!)
            }
            if tenantIDs["SimpleNFT"] == nil {
                self.SimpleNFTPackage.borrow()!.instance(tenantIDs: {"SimpleNFT": tenantIDs["NFTMarketplace"]!})
            } else {
                self.SimpleNFTPackage.borrow()!.addAlias(original: tenantIDs["SimpleNFT"]!, new: tenantIDs["NFTMarketplace"]!)
            }
            NFTMarketplace.tenants[tenantID] <-! create Tenant(_tenantID: tenantID, _holder: self.owner!.address)
            NFTMarketplace.addAlias(original: tenantID, new: tenantID)
            emit TenantCreated(id: tenantID)

            if NFTMarketplace.clientTenants[self.owner!.address] != nil {
                NFTMarketplace.clientTenants[self.owner!.address]!.append(tenantID)
            } else {
                NFTMarketplace.clientTenants[self.owner!.address] = [tenantID]
            }
        }

        pub fun addAlias(original: UInt64, new: UInt64) {
            let originalID = self.owner!.address.toString().concat(".").concat(original.toString())
            let newID = self.owner!.address.toString().concat(".").concat(new.toString())
            
            NFTMarketplace.addAlias(original: originalID, new: newID)
            emit TenantReused(id: originalID)
        }
    
        pub fun setup(tenantID: String) {
            pre {
                NFTMarketplace.tenants[tenantID] != nil: "This tenantID does not exist."
            }
            self.salecollections[tenantID] <-! create SaleCollection(tenantID, _nftPackage: self.SimpleNFTPackage, _ftPackage: self.SimpleFTPackage)
        }

        pub fun borrowSaleCollection(tenantID: String): &SaleCollection {
            let original = NFTMarketplace.aliases[tenantID]!
            if self.salecollections[original] == nil {
                self.setup(tenantID: original)
            }
            return &self.salecollections[original] as &SaleCollection
        }
        pub fun borrowSaleCollectionPublic(tenantID: String): &SaleCollection{SalePublic} {
            return self.borrowSaleCollection(tenantID: tenantID)
        }

        init(
            _SimpleNFTPackage: Capability<&SimpleNFT.Package>, 
            _SimpleFTPackage: Capability<&SimpleFT.Package>) 
        {
            self.SimpleNFTPackage = _SimpleNFTPackage
            self.SimpleFTPackage = _SimpleFTPackage
            self.salecollections <- {} 
        }

        destroy() {
            destroy self.salecollections
        }
    }

    pub fun getPackage(
        SimpleNFTPackage: Capability<&SimpleNFT.Package>, 
        SimpleFTPackage: Capability<&SimpleFT.Package>
    ): @Package {
        pre {
            SimpleNFTPackage.borrow() != nil: "This is not a correct SimpleNFT.Package! Or you don't have one yet."
        }
        return <- create Package(_SimpleNFTPackage: SimpleNFTPackage, _SimpleFTPackage: SimpleFTPackage)
    }

    /**************************************** FUNCTIONALITY ****************************************/

    pub event NFTMarketplaceInitialized()

    pub event ForSale(id: UInt64, price: UFix64)

    pub event NFTPurchased(id: UInt64, price: UFix64)

    pub event SaleWithdrawn(id: UInt64)

    pub resource interface SalePublic {
        pub fun purchase(id: UInt64, recipient: &SimpleNFT.Collection{SimpleNFT.CollectionPublic}, buyTokens: @SimpleFT.Vault)
        pub fun idPrice(id: UInt64): UFix64?
        pub fun getIDs(): [UInt64]
    }

    pub resource SaleCollection: SalePublic {
        pub let tenantID: String
        pub var forSale: {UInt64: UFix64}
        access(self) let SimpleFTPackage: Capability<&SimpleFT.Package>
        access(self) let SimpleNFTPackage: Capability<&SimpleNFT.Package>

        init (_ tenantID: String, _nftPackage: Capability<&SimpleNFT.Package>, _ftPackage: Capability<&SimpleFT.Package>,) {
            self.tenantID = tenantID
            self.forSale = {}
            self.SimpleFTPackage = _ftPackage
            self.SimpleNFTPackage = _nftPackage
        }

        pub fun unlistSale(id: UInt64) {
            self.forSale[id] = nil

            emit SaleWithdrawn(id: id)
        }

        pub fun listForSale(ids: [UInt64], price: UFix64) {
            pre {
                price > 0.0:
                    "Cannot list a NFT for 0.0"
            }

            var ownedNFTs = self.SimpleNFTPackage.borrow()!.borrowCollection(tenantID: self.tenantID).getIDs()
            for id in ids {
                if (ownedNFTs.contains(id)) {
                    self.forSale[id] = price

                    emit ForSale(id: id, price: price)
                }
            }
        }

        pub fun purchase(id: UInt64, recipient: &SimpleNFT.Collection{SimpleNFT.CollectionPublic}, buyTokens: @SimpleFT.Vault) {
            pre {
                self.forSale[id] != nil:
                    "No NFT matching this id for sale!"
                buyTokens.balance >= (self.forSale[id]!):
                    "Not enough tokens to buy the NFT!"
            }

            let price = self.forSale[id]!
            let vaultRef = self.SimpleFTPackage.borrow()!.borrowVaultPublic(tenantID: self.tenantID)
            vaultRef.deposit(vault: <-buyTokens)
            let token <- self.SimpleNFTPackage.borrow()!.borrowCollection(tenantID: self.tenantID).withdraw(withdrawID: id)
            recipient.deposit(token: <-token)
            self.unlistSale(id: id)
            emit NFTPurchased(id: id, price: price)
        }

        pub fun idPrice(id: UInt64): UFix64? {
            return self.forSale[id]
        }

        pub fun getIDs(): [UInt64] {
            return self.forSale.keys
        }
    }

    init() {
        self.clientTenants = {}
        self.tenants <- {}
        self.aliases = {}

        self.PackageStoragePath = /storage/NFTMarketplacePackage
        self.PackagePrivatePath = /private/NFTMarketplacePackage
        self.PackagePublicPath = /public/NFTMarketplacePackage

        self.metadata = HyperverseModule.ModuleMetadata(
            _title: "NFT Marketplace", 
            _authors: [HyperverseModule.Author(_address: 0x26a365de6d6237cd, _externalLink: "https://www.decentology.com/")], 
            _version: "0.0.1", 
            _publishedAt: getCurrentBlock().timestamp,
            _externalLink: "",
            _secondaryModules: [{Address(0x26a365de6d6237cd): "SimpleNFT", 0x26a365de6d6237cd: "SimpleFT"}]
        )

        emit NFTMarketplaceInitialized()
    }
}