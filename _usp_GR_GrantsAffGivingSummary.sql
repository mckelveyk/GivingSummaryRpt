USE [GIFT_REPORTING]
GO
/****** Object:  StoredProcedure [dbo].[_usp_GR_GrantsAffGivingSummary]    Script Date: 2/8/2018 3:39:08 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Kathi McKelvey
-- Create date: 1/26/2018
-- JIRA#		BI-680
-- Description:	This procedure gets CAE Data for Grants and Affilates for a given fiscal year and list of campaigns.
--				It is called from UAFReports.[dbo].[_usp_DW_GivingSummary] which is used to generate the
--				Giving Summary report.   
--
--				The table Gift_Reporting.dbo.CampaignCombinedProductionArchive is used when @FiscalYear is not the Current FY and
--				the View Gift_reporting.dbo.CAE_VIEW_PRODUCTION is used when the @FiscalYear is the current FY
--				There is one catch - data is not archived to the archived table right on 7/1 so
--				a check is made to see if data exists in the archived table and if it doesn't that means
--				the data is still in the View so the CurFYear is set to the FiscalYear parameter.
--
-- To execute Procedure:
/*
		EXEC GIFT_REPORTING.[dbo].[_usp_GR_GrantsAffGivingSummary] 
		@FiscalYear = 2017,
		@Campaigns = 'AFFBTA,AFFUSF,AFFLCA,AFFAPM'
		--'AFFUMCF,UAHS,MED,MED-PHX,PHARM,NUR,ZUCK,UaMed,AAC,ACC,ARC,FCM,OPTH,PIM,SHC,STEELE,SURGERY'

*/
-- =============================================

ALTER PROCEDURE [dbo].[_usp_GR_GrantsAffGivingSummary] (
@FiscalYear int,   -- Fiscal Year to pull data 
@Campaigns varchar(max)=null    -- list of Campaign IDs to pull data
)	
AS
BEGIN

/*  -- debugging
declare @FiscalYear int,
@Campaigns varchar(max)=null

set @FiscalYear = 2016
set @Campaigns = 'ORD,ART,ASM,CCP,BIO5,CCI,IE,LGBT'
*/

	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

    Declare  @Month int			-- current Month report is executed
			,@Year int			-- Current Calendar year report is executed
	        ,@CurFYear  int		-- current Fiscal Year

	/* PREP the Campaign selections */
	IF OBJECT_ID('tempdb..#GDCamp')>0
			DROP TABLE #GDCamp
	CREATE TABLE #GDCamp(CampaignIdentifier varchar(20))


	DECLARE @X xml
	SELECT @X = CONVERT(xml,'<root><s>' + REPLACE(@Campaigns,',','</s><s>') + '</s></root>')

	INSERT #GDCamp(CampaignIdentifier)
	SELECT [Value] = T.c.value('.','varchar(20)')
	FROM @X.nodes('/root/s') T(c)

--select * from #GDCamp  -- debugging
--drop table #GDCamp

	IF OBJECT_ID('tempdb..#Gifts')>0
			DROP TABLE #Gifts

	CREATE TABLE #Gifts (
		[GiftFactID]	int,
		[GiftSystemID]	int,
		[GiftSplitSystemID]	int,
		[DonorName] varchar(200),
		[ConstituentDimID]	int,
		[GiftAmount]	money,
		[GrantAmount] money,
		[AFFAmount] money,
		[ReceiptAmount] money,
		[CampaignDimID]	int,
		[FundDimID]	varchar(20),
		[Original_Campaign] varchar(20),
		[CampaignIdentifier] varchar(20),
		[ConstituentCode] varchar(100),
		[FundCategory] varchar(100),
		[GiftType]	varchar(100),
	)

	--  Get Current Fiscaly Year to determine which data source to use
	set @Month = MONTH(GetDate())
	set @Year = YEAR(GetDate())		
	select @CurFYear = [GIFT_REPORTING].[dbo].GetFiscalYear(@month,@Year)

--select @FiscalYear,@CurFYear       -- debugging
-- Early in the year, the FY turns to new FY but the old FY data has not been archived yet.  
-- Need to check which table contains the data for grants/affilitates and set curFY accordingly

	If @FiscalYear <> @CurFYear
	begin
	  declare @RecExist int = 0
	  select @RecExist = count(A.Name) from  dbo.CampaignCombinedProductionArchive A
			where FiscalYear = @FiscalYear and SOURCE in('SPINS','AFF') and CampaignID in (select * from #GDCamp)
	  If @RecExist = 0  -- data has not been archived yet
		set @CurFYear = @FiscalYear
	end
	--select @RecExist

	If @FiscalYear = @CurFYear            -- use View with CAE data for Current FY
	begin
	   	INSERT INTO #Gifts
		Select    0 as GiftFactID
		        , 0 as GiftSystemID
				, GIFT_SPLIT_ID as GiftSplitSystemID
				, Name as DonorName
		        , (select ConstituentDimID from BBPM_DW.dbo.DIM_Constituent C where C.ConstituentID = A.CONSTITUENT_ID) as ConstituentDimID
				, 0 as GiftAmount
		,CASE WHEN Source = 'SPINS' THEN Gift_Split_Receipt_Amount else 0 END as GrantAmount
		,CASE WHEN Source = 'AFFILIATES' THEN Gift_Split_Receipt_Amount else 0 END as AFFAmount
				, GIFT_RECEIPT_AMOUNT as ReceiptAmount
				, (Select CampaignDimID from BBPM_DW.dbo.DIM_Campaign Camp where Camp.CampaignIdentifier = A.CAMPAIGN_ID) as CampaignDimID
				, (select FundDimID from BBPM_DW.dbo.DIM_Fund F where F.FundIdentifier = A.FUND_ID) as FundDimID
				, A.CAMPAIGN_ID_RE as Original_Campaign
				, A.CAMPAIGN_ID as CampaignIdentifier
				, NULL as ConstituentCode
				, A.FUND_CATEGORY as FundCategory
				, (select GiftType from BBPM_DW.dbo.DIM_GiftType GT where GT.GiftTypeDimID = A.Gift_Type) as GiftType
 		from dbo.CAE_VIEW_PRODUCTION A
		where SOURCE in ('SPINS','AFFILIATES') and CAMPAIGN_ID in (select * from #GDCamp)
		and FISCAL_YEAR = @CurFYear
	end
	Else
	Begin
		Insert into #Gifts
		Select    0 as GiftFactID
		        , 0 as GiftSystemID
				, GIFTSPLITID as GiftSplitSystemID
				, Name as DonorName
		        , (select ConstituentDimID from BBPM_DW.dbo.DIM_Constituent C where C.ConstituentID = A.CONSTITUENTID) as ConstituentDimID
				, 0 as GiftAmount
		,CASE WHEN Source = 'SPINS' THEN GiftSplitReceiptAmount else 0 END as GrantAmount
		,CASE WHEN Source = 'AFF' THEN GiftSplitReceiptAmount else 0 END as AFFAmount
				, GIFTRECEIPTAMOUNT as ReceiptAmount
				, (select CampaignDimID from BBPM_DW.dbo.DIM_Campaign Camp where Camp.CampaignIdentifier = A.CAMPAIGNID) as CampaignDimID
				, (select FundDimID from BBPM_DW.dbo.DIM_Fund F where F.FundIdentifier = A.FUNDID) as FundDimID
				, A.CAMPAIGNIDRE as Original_Campaign
				, A.CAMPAIGNID as CampaignIdentifier
				, NULL as ConstituentCode
				, A.FUNDCATEGORY as FundCategory
				, (select GiftType from BBPM_DW.dbo.DIM_GiftType GT where GT.GiftTypeDimID = A.GiftType) as GiftType
 		from dbo.CampaignCombinedProductionArchive A
		where FiscalYear = @FiscalYear and SOURCE in('SPINS','AFF') and CampaignID in (select * from #GDCamp)
	end

	--  using RE tables to get codes.  
 	UPDATE		#Gifts
	SET			ConstituentCode = G.ConstituentCode
	FROM
	  (Select CON.ConstituentDimID 
			,(SELECT TOP 1 (select LongDescription FROM [REDW].[dbo].[TABLEENTRIES] T
			  where T.TABLEENTRIESID = CC.CODE) as ConstituentCode
			  FROM [REDW].[dbo].[CONSTITUENT_CODES] CC
	   where CONSTIT_ID = CON.ConstituentDimID) as ConstituentCode
	   from #Gifts CON) as G
	WHERE	  #Gifts.ConstituentDimID = G.ConstituentDimID 

	Select * from #Gifts
END
