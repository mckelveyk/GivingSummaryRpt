USE [UAFreports]
GO
/****** Object:  StoredProcedure [dbo].[_usp_DW_GivingSummary]    Script Date: 2/21/2018 9:55:49 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* ==========================================================================================================================================================
 Author:				K. McKelvey
 Create Date:			1/17/2018
 JIRA:					BI-680
 Description:			Pulls the RE Gifts, Grants and Affilates gifts for the 
						Giving Summary report.  It uses the Hierarchy table UDPGroups 
						to get the subordinate campaigns and Affilates.  
						# of Donors, # of Gifts and Total Gift $ is calculated based on the 
						Fiscal Year, Campaigns and @pRptCode.

						Grants and Affiliates are not included in the Category totals.  They are
						displayed as a separate row.  

						This procedure is called by the Giving Sumary report for each dataset
						using the @pRptCode parameter to group the query based on the following:

						1 - Constituent Codes
						2 - Fund Category
						3 - Gift Type

						Procedure calls are made to get the gifts:
						UAFReports.dbo._usp_DW_GivingSummaryGiftDetail (RE Gifts)
						GIFT_REPORTING.dbo._usp_GR_GrantsAffGivingSummary  (Grants and Affiliates)

 EXEC [dbo].[_usp_DW_GivingSummary]
	@pFiscalYear = 2018,
	@pCampaignID = 'CALA,CALS,CFA,DIVPROG,ED,ELLER,ENG,GRAD,HON,HUM,LAW,LIB,NICD,OpSci,PRESENTS,SBS,SCI' ,
	--'AAC,ACC,AG,ALUM,ARC,ART,ASM,BIO5,CALA,CALS,CCI,CCP,CFA,DEV,DIVPROG,ED,ELLER,ENG,FCM,GRAD,HON,HUM,ICA,IE,KUAT,LAW,LGBT,LIB,MED,MED-PHX,NICD,NUR,OpSci,OPTH,PHARM,PIM,PRESENTS,RDI,REST,SBS,SCHOL,SCI,SHC,SLS,STEELE,SURGERY,UAHS,UAMed,UNRES,ZUCK' ,
	--'ART,ASM,BIO5,CCI,CCP,IE,LGBT,RDI',
	--'ALUM,KUAT,CALS,CALA,ED,ENG,CFA,HUM,OpSci,SBS,SCI,ELLER,GRAD,HON,LAW,SCHOL,SLS,LIB,RDI,ICA,UAHS,REST,',
	@pRptCode =  3 --'Constituent Code'

==========================================================================================================================================================*/

ALTER PROCEDURE [dbo].[_usp_DW_GivingSummary] (
	@pFiscalYear smallint=NULL,   
	@pCampaignID varchar(max)= null, 
	@pRptCode varchar(50)
)
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	
	declare @AllGiftLevels varchar(max)=null  -- concatenate all gift levels into one string
	declare @NumGiftLevelRecs int
	declare @RowCount int
	declare @GLID int  -- Gift Level ID from UAFReports.vw_Dim_GoalAmts	
	declare @UnitName varchar(10)
	declare @NumSubCampRecs int 
	declare @CampaignIdentifers varchar(max)    -- common string of Campaign IDs
	declare @CampaignIDList table (				-- common list of Campaign IDs
	  CampID varchar(20)
	 )


	set @CampaignIdentifers = @pCampaignID
	-- handle multiple selections for the Campaign ID
	SELECT Item
	INTO #CAMPAIGN_LIST 
	FROM GIFT_REPORTING.dbo.DelimitedSplit8k(@pCampaignID,','); 
	insert into @CampaignIDList (CampID)  -- Store all Selected in report parameter Campaign IDs
	select Item from #CAMPAIGN_LIST

--select * from #CAMPAIGN_LIST							-- debugging
	declare  @CampaignTotals table(
	Campaign varchar(20),
	CampaignGifts money,	-- RE Gifts
	CampaignGrants money,   -- Grants
	CampaignAFF money,		-- Affiliates
	CampGiftTotalYTD money,
	CampTotalGoalAmt  money,
	CampPercToGoal money
    unique clustered (Campaign)
    )

	-- store the Gift Level IDs from UAFReports.vw_Dim_GoalAmts 
	set @AllGiftLevels = stuff((select ',' + convert(varchar(2),GiftLevelID) from [dbo].[vw_Dim_GoalAmts] 
	where ((GiftLevelID between 1 and 10) or GiftLevelID = 14)	 FOR XML PATH('')),1,1,'')
		
	IF OBJECT_ID('tempdb..#GiftDetail')>0
			DROP TABLE #GiftDetail

	CREATE TABLE #GiftDetail (
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

--select @CampaignIdentifers						-- debugging

	-- Get RE Gifts from DW
	INSERT INTO #GiftDetail
	EXEC [dbo].[_usp_DW_GivingSummaryGiftDetail] 
		@FiscalYear = @pFiscalYear,
		@Campaigns = @CampaignIdentifers,
		@GiftLevel = @AllGiftLevels			

--select * from #GiftDetail							-- debugging
--truncate table #GiftDetail
--select @CampaignIdentifers

--  Concatenate the associate Affilliates campaign IDs to get gifts 
	Declare @CampaignList varchar(max)
	EXEC dbo._usp_CreateCampaignStringWithAffiliates @pFiscalYear, @CampaignIdentifers, 'None', @CampaignList output
--select @CampaignList

	-- Get Grants and Affilates from CAE
	INSERT INTO #GiftDetail
	EXEC GIFT_REPORTING.[dbo].[_usp_GR_GrantsAffGivingSummary] 
		@FiscalYear = @pFiscalYear,
		@Campaigns = @CampaignList

--select * from #GiftDetail							 -- debugging

	-- update FundCategory when it is blank to NULL
	-- this is necessary because blank values need to be listed at the end of the list of 
	-- Fund Categories on report.  Setting them to Null is used to set them to "X" for ordering.
	update #GiftDetail
	set FundCategory = NULL
	from #GiftDetail
	Where FundCategory = ''

	-- sort Gifts by RptCode and calculate # of Donors, # of Gifts and $ Gifts
	-- # of Donors and # of Gifts for Affiliates is not calculated
	-- because Affiliates gives us their totals by lumping all their individual donors 
	-- into one count - report will show "N/A" for these fields
	If @pRptCode = 1 -- = 'Constituent Code'
	  Begin
		select ConstituentCode as 'TableType', 
			   count(distinct ConstituentDimID) as NumofDonors,
		       count(GiftAmount) as NumofGifts,
			   sum(GiftAmount) as TotalGifts,
			   (select count(distinct ConstituentDimID) from #GiftDetail
			    where GiftAmount > 0) as Donors_REGiftTotal ,
			   (select count(GiftAmount) from #GiftDetail
			    where GiftAmount > 0) as Gifts_REGiftTotal,
			   (select sum(GiftAmount) from #GiftDetail
			    where GiftAmount > 0) as Amount_REGiftTotal,
			   (select count(distinct DonorName) from #GiftDetail
			    where GrantAmount > 0) as Donors_GrantTotal ,
			   (select count(GrantAmount) from #GiftDetail
			    where GrantAmount > 0) as Gifts_GrantTotal,
			   (select sum(GrantAmount) from #GiftDetail
			    where GrantAmount > 0) as Amount_GrantTotal,
			   (select sum(AFFAmount) from #GiftDetail
			    where AFFAmount > 0) as Amount_AFFTotal
		from #GiftDetail
		where GiftAmount > 0  -- Constituent Code Category rows are only for RE Gifts
		group by ConstituentCode
		order by TableType
	  End
	Else if @pRptCode = 2 -- = 'Fund Category'
	  Begin
		select isnull(FundCategory,'X') as 'TableType',  
			   count(distinct ConstituentDimID) as NumofDonors,
		       count(GiftAmount) as NumofGifts,
			   sum(GiftAmount)  as TotalGifts,
			   (select count(distinct ConstituentDimID) from #GiftDetail
			    where GiftAmount > 0) as Donors_REGiftTotal ,
			   (select count(GiftAmount) from #GiftDetail
			    where GiftAmount > 0) as Gifts_REGiftTotal,
			   (select sum(GiftAmount) from #GiftDetail
			    where GiftAmount > 0) as Amount_REGiftTotal,
			   (select count(distinct DonorName) from #GiftDetail
			    where GrantAmount > 0) as Donors_GrantTotal ,
			   (select count(GrantAmount) from #GiftDetail
			    where GrantAmount > 0) as Gifts_GrantTotal,
			   (select sum(GrantAmount) from #GiftDetail
			    where GrantAmount > 0) as Amount_GrantTotal,
			   (select sum(AFFAmount) from #GiftDetail
			    where AFFAmount > 0) as Amount_AFFTotal
		from #GiftDetail
		where GiftAmount > 0		 -- Fund Category rows are only for RE Gifts
		group by FundCategory
		order by TableType
      End
	Else -- 3 = 'Gift Type'
	  Begin
		select isnull(GiftType,'X') as 'TableType',  
			   count(distinct ConstituentDimID) as NumofDonors,
		       count(GiftAmount) as NumofGifts,
			   sum(GiftAmount) as TotalGifts,
			   (select count(distinct ConstituentDimID) from #GiftDetail
			    where GiftAmount > 0) as Donors_REGiftTotal ,
			   (select count(GiftAmount) from #GiftDetail
			    where GiftAmount > 0) as Gifts_REGiftTotal,
			   (select sum(GiftAmount) from #GiftDetail
			    where GiftAmount > 0) as Amount_REGiftTotal,
			   (select count(distinct DonorName) from #GiftDetail
			    where GrantAmount > 0) as Donors_GrantTotal ,
			   (select count(GrantAmount) from #GiftDetail
			    where GrantAmount > 0) as Gifts_GrantTotal,
			   (select sum(GrantAmount) from #GiftDetail
			    where GrantAmount > 0) as Amount_GrantTotal,
			   (select sum(AFFAmount) from #GiftDetail
			    where AFFAmount > 0) as Amount_AFFTotal
		from #GiftDetail
		where GiftAmount > 0		 -- Gift Type Category rows are only for RE Gifts
		group by GiftType
		order by TableType
      End

END
