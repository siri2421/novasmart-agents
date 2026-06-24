-- =========================================================================
-- NovaSmart Pricing Catalog: 25 Items and Competitor Dataset Seed Script
-- Datasets: novasmart_pricing, competitor_data
-- =========================================================================

-- 1. Create the Schema / Dataset if it doesn't exist
CREATE SCHEMA IF NOT EXISTS `novasmart_pricing`;
CREATE SCHEMA IF NOT EXISTS `competitor_data`;

-- 2. Create the Inventory Table
CREATE OR REPLACE TABLE `novasmart_pricing.inventory` (
  sku STRING OPTIONS(description="Unique product stock keeping unit identifier"),
  product_name STRING OPTIONS(description="Human-readable name of the product"),
  category STRING OPTIONS(description="Product retail category"),
  shelf_price NUMERIC OPTIONS(description="Active retail shelf price in USD"),
  local_stock INT64 OPTIONS(description="Number of units currently in stock at this store"),
  days_since_last_sale INT64 OPTIONS(description="Number of days since this product was last purchased")
);

-- 3. Create the Wholesale Costs Table (Siloed financial data)
CREATE OR REPLACE TABLE `novasmart_pricing.wholesale_costs` (
  sku STRING OPTIONS(description="Unique product stock keeping unit identifier"),
  wholesale_cost NUMERIC OPTIONS(description="Wholesale cost paid to manufacturer in USD"),
  margin_floor NUMERIC OPTIONS(description="Absolute minimum approved selling price in USD")
);

-- 4. Create the Competitor Prices Table
CREATE OR REPLACE TABLE `competitor_data.prices` (
  sku STRING OPTIONS(description="Unique product stock keeping unit identifier"),
  competitor_name STRING OPTIONS(description="Name of the competitor store"),
  competitor_price NUMERIC OPTIONS(description="Competitor retail price in USD"),
  competitor_stock INT64 OPTIONS(description="Competitor stock level")
);

-- 5. Seed the 25 Items (5 per category)
-- =========================================================================

-- CATEGORY 1: HOUSEHOLD ELECTRONICS
-- Barista Pro Espresso Machine (Escalation target for discount scenarios)
INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-HSE-4455', 'Barista Pro Espresso Machine', 'Household Electronics', 450.00, 18, 40);
INSERT INTO `competitor_data.prices` VALUES ('SKU-HSE-4455', 'AlphaStore', 427.50, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-HSE-4455', 'BetaBuy', 382.50, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-HSE-4455', 290.00, 310.00);
-- Competitors for SKU-HSE-4455:
-- 1. AlphaStore: Price is 410.00 (8.89% discount < 12%), stock is 20
-- 2. BetaBuy: Price is 380.00 (15.56% discount > 12%), stock is 50 (High stock -> Approve match)
-- 3. GammaOutlet: Price is 375.00 (16.67% discount > 12%), stock is 2 (Low stock -> Reject match)

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-HSE-4001', 'AeroPure Smart Air Purifier', 'Household Electronics', 349.00, 15, 3);
INSERT INTO `competitor_data.prices` VALUES ('SKU-HSE-4001', 'AlphaStore', 331.55, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-HSE-4001', 'BetaBuy', 296.65, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-HSE-4001', 220.00, 240.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-HSE-4002', 'TerraMow Robotic Lawn Mower', 'Household Electronics', 1499.00, 4, 18);
INSERT INTO `competitor_data.prices` VALUES ('SKU-HSE-4002', 'AlphaStore', 1424.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-HSE-4002', 'BetaBuy', 1274.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-HSE-4002', 950.00, 1100.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-HSE-4003', 'OmniClean Robot Vacuum Pro', 'Household Electronics', 899.00, 9, 6);
INSERT INTO `competitor_data.prices` VALUES ('SKU-HSE-4003', 'AlphaStore', 854.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-HSE-4003', 'BetaBuy', 764.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-HSE-4003', 600.00, 680.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-HSE-4004', 'Spectra 4K Laser Projector', 'Household Electronics', 2799.00, 3, 21);
INSERT INTO `competitor_data.prices` VALUES ('SKU-HSE-4004', 'AlphaStore', 2659.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-HSE-4004', 'BetaBuy', 2379.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-HSE-4004', 1800.00, 2000.00);


-- CATEGORY 2: LAPTOPS & COMPUTING
INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-LPT-1001', 'Titanium Book Pro 16', 'Laptops & Computing', 2499.00, 4, 15);
INSERT INTO `competitor_data.prices` VALUES ('SKU-LPT-1001', 'AlphaStore', 2374.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-LPT-1001', 'BetaBuy', 2124.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-LPT-1001', 1700.00, 1900.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-LPT-1002', 'AeroGrid Gaming Laptop', 'Laptops & Computing', 1899.00, 8, 5);
INSERT INTO `competitor_data.prices` VALUES ('SKU-LPT-1002', 'AlphaStore', 1804.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-LPT-1002', 'BetaBuy', 1614.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-LPT-1002', 1300.00, 1450.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-LPT-1003', 'VaporGlide Ultra-Thin 14', 'Laptops & Computing', 1299.00, 15, 2);
INSERT INTO `competitor_data.prices` VALUES ('SKU-LPT-1003', 'AlphaStore', 1234.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-LPT-1003', 'BetaBuy', 1104.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-LPT-1003', 850.00, 950.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-LPT-1004', 'Zenith Developer Workstation', 'Laptops & Computing', 2999.00, 3, 28);
INSERT INTO `competitor_data.prices` VALUES ('SKU-LPT-1004', 'AlphaStore', 2849.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-LPT-1004', 'BetaBuy', 2549.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-LPT-1004', 2000.00, 2200.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-LPT-1005', 'Chromium CloudBook Enterprise', 'Laptops & Computing', 899.00, 22, 1);
INSERT INTO `competitor_data.prices` VALUES ('SKU-LPT-1005', 'AlphaStore', 854.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-LPT-1005', 'BetaBuy', 764.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-LPT-1005', 600.00, 670.00);


-- CATEGORY 3: PERSONAL MOBILE ELECTRONICS
INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-MOB-2001', 'Apex 5G Foldable Smartphone', 'Personal Mobile Electronics', 1799.00, 12, 4);
INSERT INTO `competitor_data.prices` VALUES ('SKU-MOB-2001', 'AlphaStore', 1709.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-MOB-2001', 'BetaBuy', 1529.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-MOB-2001', 1200.00, 1350.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-MOB-2002', 'NovaPhone Ultra 26', 'Personal Mobile Electronics', 1199.00, 18, 1);
INSERT INTO `competitor_data.prices` VALUES ('SKU-MOB-2002', 'AlphaStore', 1139.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-MOB-2002', 'BetaBuy', 1019.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-MOB-2002', 800.00, 900.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-MOB-2003', 'VaporTalk Sat-Phone Pro', 'Personal Mobile Electronics', 1499.00, 5, 19);
INSERT INTO `competitor_data.prices` VALUES ('SKU-MOB-2003', 'AlphaStore', 1424.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-MOB-2003', 'BetaBuy', 1274.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-MOB-2003', 1050.00, 1180.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-MOB-2004', 'Quantum Watch Active 5', 'Personal Mobile Electronics', 399.00, 40, 2);
INSERT INTO `competitor_data.prices` VALUES ('SKU-MOB-2004', 'AlphaStore', 379.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-MOB-2004', 'BetaBuy', 339.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-MOB-2004', 260.00, 290.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-MOB-2005', 'AeroGlass AR Smart Glasses', 'Personal Mobile Electronics', 699.00, 8, 14);
INSERT INTO `competitor_data.prices` VALUES ('SKU-MOB-2005', 'AlphaStore', 664.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-MOB-2005', 'BetaBuy', 594.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-MOB-2005', 450.00, 520.00);


-- CATEGORY 4: AUDIO & ACOUSTICS
INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-AUD-3001', 'SonicDome ANC Headphones', 'Audio & Acoustics', 349.00, 25, 2);
INSERT INTO `competitor_data.prices` VALUES ('SKU-AUD-3001', 'AlphaStore', 331.55, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-AUD-3001', 'BetaBuy', 296.65, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-AUD-3001', 220.00, 250.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-AUD-3002', 'VaporBuds Pro Wireless', 'Audio & Acoustics', 199.00, 45, 1);
INSERT INTO `competitor_data.prices` VALUES ('SKU-AUD-3002', 'AlphaStore', 189.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-AUD-3002', 'BetaBuy', 169.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-AUD-3002', 120.00, 140.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-AUD-3003', 'AuraSound Studio Monitors', 'Audio & Acoustics', 899.00, 6, 18);
INSERT INTO `competitor_data.prices` VALUES ('SKU-AUD-3003', 'AlphaStore', 854.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-AUD-3003', 'BetaBuy', 764.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-AUD-3003', 580.00, 650.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-AUD-3004', 'Matrix SoundBar Surround 9.1', 'Audio & Acoustics', 1199.00, 8, 9);
INSERT INTO `competitor_data.prices` VALUES ('SKU-AUD-3004', 'AlphaStore', 1139.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-AUD-3004', 'BetaBuy', 1019.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-AUD-3004', 780.00, 880.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-AUD-3005', 'Zenith Audiophile DAC/Amp', 'Audio & Acoustics', 599.00, 7, 31);
INSERT INTO `competitor_data.prices` VALUES ('SKU-AUD-3005', 'AlphaStore', 569.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-AUD-3005', 'BetaBuy', 509.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-AUD-3005', 380.00, 440.00);


-- CATEGORY 5: SMART WEARABLES & GEAR
INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-WRB-5001', 'PixelLens VR Headset Pro', 'Smart Wearables & Gear', 1299.00, 8, 16);
INSERT INTO `competitor_data.prices` VALUES ('SKU-WRB-5001', 'AlphaStore', 1234.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-WRB-5001', 'BetaBuy', 1104.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-WRB-5001', 850.00, 950.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-WRB-5002', 'AeroView Action Cam 8K', 'Smart Wearables & Gear', 499.00, 15, 4);
INSERT INTO `competitor_data.prices` VALUES ('SKU-WRB-5002', 'AlphaStore', 474.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-WRB-5002', 'BetaBuy', 424.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-WRB-5002', 320.00, 360.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-WRB-5003', 'Quantum Fit Band 3', 'Smart Wearables & Gear', 149.00, 42, 1);
INSERT INTO `competitor_data.prices` VALUES ('SKU-WRB-5003', 'AlphaStore', 141.55, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-WRB-5003', 'BetaBuy', 126.65, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-WRB-5003', 90.00, 105.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-WRB-5004', 'VaporTrek Golf GPS Watch', 'Smart Wearables & Gear', 299.00, 14, 8);
INSERT INTO `competitor_data.prices` VALUES ('SKU-WRB-5004', 'AlphaStore', 284.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-WRB-5004', 'BetaBuy', 254.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-WRB-5004', 180.00, 210.00);

INSERT INTO `novasmart_pricing.inventory` VALUES ('SKU-WRB-5005', 'AuraScope NightVision Binoculars', 'Smart Wearables & Gear', 399.00, 6, 25);
INSERT INTO `competitor_data.prices` VALUES ('SKU-WRB-5005', 'AlphaStore', 379.05, 10);
INSERT INTO `competitor_data.prices` VALUES ('SKU-WRB-5005', 'BetaBuy', 339.15, 10);
INSERT INTO `novasmart_pricing.wholesale_costs` VALUES ('SKU-WRB-5005', 250.00, 280.00);

-- =========================================================================
-- End of Seed Script. 25 items and competitor records successfully declared.
-- =========================================================================
