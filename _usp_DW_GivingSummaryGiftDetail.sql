USE [UAFreports]
GO
/****** Object:  StoredProcedure [dbo].[_usp_DW_GivingSummaryGiftDetail]    Script Date: 2/21/2018 10:15:37 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/* ==========================================================================================
 Author:				K. McKelvey
 Create Date:			1/17/2018
 JIRA:					BI-680
 Description:			Pulls the RE Gifts for the Giving Summary report for a certain
						Fiscal Year, Campaigns and Gift Levels. 
						Excludes Banner University Medical Center constituent for all time
						ConstituentDimID = 2346877 

						Some of the fields and joins in the Select statement came 
						from [dbo].[_usp_ForecastingByGiftLevel_GiftDetail].  You will notice some 
						comments that refer to changes and reasons for the code. 


 EXEC [dbo].[_usp_DW_GivingSummaryGiftDetail]
	@FiscalYear = 2017,
	@Campaigns = 'ALUM,KUAT,CALS,CALA,ED,ENG,CFA,HUM,OpSci,SBS,SCI,ELLER,GRAD,HON,LAW,SCHOL,SLS,LIB,RDI,ICA,UAHS,REST,UAF',
	@GiftLevel = '1,2,3,4,5,6,7,8,9,10,14'

=============================================================================================
*/
ALTER PROCEDURE [dbo].[_usp_DW_GivingSummaryGiftDetail] (
	@FiscalYear smallint=null,
	@Campaigns varchar(max)=null,
	@GiftLevel varchar(max)=null   ---smallint=null  -- changed by KM 6/29/2016
)
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;
	
	DECLARE @DefaultCampaignIdentifier varchar(20);
	SELECT @DefaultCampaignIdentifier = CampaignIdentifier from [BBPM_DW].dbo.DIM_Campaign where CampaignDimID = '117'

	/* PREP the Campaign selections */
	IF OBJECT_ID('tempdb..#GDCamp')>0
			DROP TABLE #GDCamp
	CREATE TABLE #GDCamp(CampaignIdentifier varchar(20))

	
	DECLARE @X xml
	SELECT @X = CONVERT(xml,'<root><s>' + REPLACE(@Campaigns,',','</s><s>') + '</s></root>')

	INSERT #GDCamp(CampaignIdentifier)
	SELECT [Value] = T.c.value('.','varchar(20)')
	FROM @X.nodes('/root/s') T(c)
	/* PREP the Campaign selections */


	/* PREP Gift Level Selections */  
	IF OBJECT_ID('tempd..#GDGiftLevel')>0
			DROP TABLE #GDGiftLevel
	CREATE TABLE #GDGiftLevel(CategoryGoalDimID int)


	SELECT @X = CONVERT(xml,'<root><s>' + REPLACE(@GiftLevel,',','</s><s>') + '</s></root>')

	INSERT #GDGiftLevel(CategoryGoalDimID)
	SELECT [Value] = T.c.value('.','int')
	FROM @X.nodes('/root/s') T(c)	
	/* PREP Gift Level Selections */

	Select
		  G.[GiftFactID]
		, G.[GiftSystemID]
		, G.[GiftSplitSystemID]
		, (select FullName from BBPM_DW.dbo.DIM_Constituent C where C.ConstituentDimID = G.ConstituentDimID) as DonorName
		, G.[ConstituentDimID]
		, G.[GiftDateDimID]
		, G.[GiftTypeDimID]
		, G.[Amount]
		, G.[ReceiptAmount]
		, G.[CampaignDimID]
		, G.[FundDimID]
		, G.[CreditType]
		, C.[CampaignIdentifier] as Original_CampaignIdentifier
		, CASE 
			WHEN C.[CampaignIdentifier] = 'AG' 
			THEN COALESCE(Try1.CampaignIdentifier, Try2.CampaignIdentifier, Try3.CampaignIdentifier, Try4.CampaignIdentifier, @DefaultCampaignIdentifier)
			ELSE C.[CampaignIdentifier] 
		END AS CampaignIdentifier
			--This Calculates a new Appeal Identifier for us to use in cases where it's an AG (Annual Giving) gift. The function was written by Javier at UAF.
	into #Gifts
	FROM [BBPM_DW].[dbo].FACT_Gift G
	LEFT JOIN BBPM_DW.dbo.DIM_Campaign C ON isnull(G.CampaignDimID, -1) = C.CampaignDimID
	LEFT JOIN BBPM_DW.dbo.DIM_Fund Fnd ON G.FundDimID = Fnd.FundDimID
	LEFT JOIN BBPM_DW.dbo.DIM_FundAttribute CUName ON G.FundDimID = CUName.FundDimID AND CUName.AttributeCategory = 'College/Unit Name'
	--Join to Each Match-Case scenario to get the right AppealID designation for AG Gifts: JAVIER: This was described in the AG Overview document
	LEFT JOIN (
		Select DC.CampaignIdentifier, DF.[FundIdentifier]
		from [BBPM_DW].[dbo].[DIM_Fund] DF
		join [BBPM_DW].[dbo].DIM_Campaign DC ON DC.CampaignDimID = DF.CampaignDimID
		where DF.CampaignDimID <> '117' and DF.CampaignDimID <> '-1' --Javier added on 2/6/2017
	) Try1 ON Try1.[FundIdentifier]=Fnd.[FundIdentifier]
	LEFT JOIN (
		Select DC.CampaignIdentifier, DF.[FundIdentifier]	
		from [BBPM_DW].[dbo].[DIM_Fund] DF 
		join [BBPM_DW].[dbo].[DIM_FundAttribute] DFA on DF.FundDimID = DFA.FundDimID
		join [BBPM_DW].[dbo].DIM_Campaign DC ON DC.CampaignDescription = DFA.AttributeDescription
		where AttributeCategory = 'College/Unit Name'
	) Try2 ON Try2.[FundIdentifier]=Fnd.[FundIdentifier]
	LEFT JOIN (
		Select AGLP.CAMPAIGN_ID as CampaignIdentifier, AGLP.FUND_ID as FundIdentifier
		from [GIFT_REPORTING].dbo.AG_CAMPAIGN_LINK_PRODUCTION AGLP  --JAVIER: this is a table that links the AG items to a Campaign ID
	) Try3 ON Try3.[FundIdentifier]=Fnd.[FundIdentifier]
	LEFT JOIN (
		Select CAMPAIGN_ID as CampaignIdentifier, [DESCRIPTION] as CUN_AttributeDescription
		from [GIFT_REPORTING].dbo.CAE_LOOKUP_CAMPAIGN_PRODUCTION --JAVIER: this contains attribute descriptions that are tied to a Campaign ID 
	) Try4 ON Try4.CUN_AttributeDescription = CUName.[AttributeDescription]
			
	LEFT JOIN BBPM_DW.dbo.DIM_Date DA ON G.GiftDateDimID = DA.DateDimID	
			
	WHERE G.ReceiptAmount > 0 --JCA Added on 12/10/2015 to Exclude Non-Gifts from the results of the Report
			and G.GiftFactID not in (select GiftfactID from bbpm_DW.dbo.Fact_Gift FG
			where FG.ConstituentDimID = 2346877 ) -- exclude Banner University Medical Center constituent


	CREATE INDEX IX_Gifts_GiftFactID 
		ON #Gifts(GiftFactID)

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

	-- need to define the temp table because it is needed to update the
	-- constituent code after query.
	-- Can't put constituent Code in query because due to the Top 1 clause
	-- it results in query taking a very long time to complete for all campaigns (@20 mins)
	INSERT INTO #GiftDetail ([GiftFactID],
		[GiftSystemID],
		[GiftSplitSystemID],
		[DonorName],
		[ConstituentDimID]	,
		[GiftAmount]	,
		[GrantAmount] ,
		[AFFAmount] ,
		[ReceiptAmount] ,
		[CampaignDimID]	,
		[FundDimID]	,
		[Original_Campaign] ,
		[CampaignIdentifier] ,
		[FundCategory] ,
		[GiftType]
		)
	SELECT G.GiftFactID
		, G.GiftSystemID, G.GiftSplitSystemID
		, G.DonorName
		, G.ConstituentDimID
		, G.Amount as GiftAmount
		, 0 as GrantAmount
		, 0 as AFFAmount
		, G.ReceiptAmount
		, G.CampaignDimID
		, G.FundDimID
		, G.Original_CampaignIdentifier AS Original_CampaignIdentifier
		, G.CampaignIdentifier
		, (select FundCategoryDescription from BBPM_DW.dbo.DIM_Fund F where F.FundDimID = G.FundDimid) as FundCategory
		, gt.GiftType
	FROM #Gifts G 
	JOIN #GDCamp CC ON G.CampaignIdentifier = CC.CampaignIdentifier --Filter results by Campaign list from parameter
	LEFT JOIN [BBPM_DW].[dbo].DIM_Date D
		ON G.GiftDateDimID = D. DateDimID
	LEFT JOIN [BBPM_DW].[dbo].DIM_Constituent pC
		ON G.ConstituentDimID = pC.ConstituentDimID
	INNER JOIN (SELECT GiftTypeDimID, GiftType FROM [BBPM_DW].[dbo].DIM_GiftType WHERE GiftTypeDimID IN (1,8,9,10,15,18,27,31,34)) gt
		ON G.GiftTypeDimID = gt.GiftTypeDimID
	LEFT JOIN [dbo].[vw_Dim_GoalAmts] GL ON G.Amount BETWEEN GL.Min_Dollar and GL.Max_Dollar
	JOIN #GDGiftLevel GL_IN ON GL_IN.CategoryGoalDimID = GL.GiftLevelID   -- added by KM 6/29/2016
	LEFT JOIN [BBPM_DW].[dbo].DIM_Fund fund
		ON G.FundDimID = fund.FundDimID
	WHERE D.FiscalYear = @FiscalYear
	AND G.CreditType = 'HC'
    ORDER BY GL.GiftLevel

-- update temp table to pull constituent code for constituent.  You need to pull using
-- the Top 1 clause because there can be more than 1 constituent code with IsPrimary = 1. 
-- It's necessary to get the Constituent Code from RE Table.  There is a hierarchy order 
-- for constituent codes implemented in RE but not carried over to the DW.  The DW has
-- ConstituentConstitCodeSystemID that you can order using descending to get the latest however
-- we don't always want the latest.  If the constituent is an alumnus then Alumnus is always the Code
-- regardless if they go back to school as a Graduate student.  Another example is if a 
-- constituent is a Non Grad and then a Parent, we want Non Grad to be pulled.  RE has Non Grad
-- as the first code in table whereas DW will have Parent as first row. 
-- this CDIMID: 2100651 does not pull correctly in DW but is correct in RE.  It should pull Parent
-- but DW is pulling Student.    
 
 --  using RE tables to get codes.  
 	UPDATE		#GiftDetail
	SET			ConstituentCode = G.ConstituentCode
	FROM
	  (Select CON.ConstituentDimID 
			,(SELECT TOP 1 (select LongDescription FROM [REDW].[dbo].[TABLEENTRIES] T
			  where T.TABLEENTRIESID = CC.CODE) as ConstituentCode
			  FROM [REDW].[dbo].[CONSTITUENT_CODES] CC
	          where CONSTIT_ID = CON.ConstituentDimID) as ConstituentCode
			 
	   from #GiftDetail CON) as G
	WHERE	  #GiftDetail.ConstituentDimID = G.ConstituentDimID 

	SELECT  [GiftFactID],
			[GiftSystemID],
			[GiftSplitSystemID],
			[DonorName],
			[ConstituentDimID],
			[GiftAmount],
			[GrantAmount],
			[AFFAmount],
			[ReceiptAmount],
			[CampaignDimID],
			[FundDimID],
			[Original_Campaign],
			[CampaignIdentifier],
			[ConstituentCode],
			[FundCategory],
			[GiftType]
	FROM #GiftDetail
END

