USE [UAFreports]
GO
/****** Object:  StoredProcedure [dbo].[_usp_SetDefaultValuesForCampaigns]    Script Date: 2/21/2018 4:37:21 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



/* ==========================================================================================
 Author:		K. McKelvey
 Create date:	02/21/2018
 Description:	This Procedure is called from reports to retrieve a list of subordinate campaigns
				for the Campaign Group selected on report.  If Campaign Group = 'None' then a list of
				all Campaigns will be created without the selection of "None" in the list.

EXEC [_usp_SetDefaultValuesForCampaignList] 'None'


=============================================================================================
*/
create PROCEDURE [dbo].[_usp_SetDefaultValuesForCampaignList] (
	@pCampaignDefaults varchar(20)

)
AS
BEGIN

--declare @CampaignDefaults varchar(5)  -- debugging
--set @CampaignDefaults = 'UAHS'
DECLARE @CurrentCampaigns hierarchyid

if @pCampaignDefaults = 'UAHS' 
Begin
	SELECT @CurrentCampaigns = GroupNode
	FROM UDPGroups
	WHERE UnitID = 7;  -- get all under UAHS 

	SELECT '(' + UnitName + ') ' + (select CampaignDescription from BBPM_DW.dbo.Dim_Campaign C where C.CampaignIdentifier = UnitName) as  Label ,
	UnitName as Value, ROW_NUMBER() OVER(order by UnitName) AS Sort
	FROM UDPGroups
	WHERE GroupNode.GetAncestor(1) = @CurrentCampaigns  and UnitName <> 'AFFUMCF'
	order by Sort
end
else if @pCampaignDefaults = 'PROVOST' 
begin
	Declare @PROVOSTCampaignList Table ( Label varchar(500), Value varchar(20),Sort int)

SELECT @CurrentCampaigns = GroupNode
	FROM UDPGroups
	WHERE UnitID = 2 ;  -- get all under PROVOST 

	insert into @PROVOSTCampaignList (Label, Value, Sort)
	SELECT '(' + UnitName + ') ' + (select CampaignDescription from BBPM_DW.dbo.Dim_Campaign C where C.CampaignIdentifier = UnitName) as  Label ,
	UnitName as Value, ROW_NUMBER() OVER(order by UnitName) AS Sort
	FROM UDPGroups
	WHERE GroupNode.GetAncestor(1) = @CurrentCampaigns 
	order by Sort

	SELECT @CurrentCampaigns = GroupNode
	FROM UDPGroups
	WHERE UnitID = 8 ;  -- get all under PROVOST - CFA 

	insert into @PROVOSTCampaignList (Label, Value, Sort)
	SELECT '(' + UnitName + ') ' + (select CampaignDescription from BBPM_DW.dbo.Dim_Campaign C where C.CampaignIdentifier = UnitName) as  Label ,
	UnitName as Value, ROW_NUMBER() OVER(order by UnitName) AS Sort
	FROM UDPGroups
	WHERE GroupNode.GetAncestor(1) = @CurrentCampaigns and UnitName <> 'CFA'
	order by Sort

	SELECT @CurrentCampaigns = GroupNode
	FROM UDPGroups
	WHERE UnitID = 9 ;  -- get all under PROVOST - SBS 

	insert into @PROVOSTCampaignList (Label, Value, Sort)
	SELECT '(' + UnitName + ') ' + (select CampaignDescription from BBPM_DW.dbo.Dim_Campaign C where C.CampaignIdentifier = UnitName) as  Label ,
	UnitName as Value, ROW_NUMBER() OVER(order by UnitName) AS Sort
	FROM UDPGroups
	WHERE GroupNode.GetAncestor(1) = @CurrentCampaigns  and UnitName <> 'SBS'
	order by Sort

	SELECT @CurrentCampaigns = GroupNode
	FROM UDPGroups
	WHERE UnitID = 11 ;  -- get all under UA MAIN - ALUM 

	insert into @PROVOSTCampaignList (Label, Value, Sort)
	SELECT '(' + UnitName + ') ' + (select CampaignDescription from BBPM_DW.dbo.Dim_Campaign C where C.CampaignIdentifier = UnitName) as  Label ,
	UnitName as Value, ROW_NUMBER() OVER(order by UnitName) AS Sort
	FROM UDPGroups
	WHERE GroupNode.GetAncestor(1) = @CurrentCampaigns  and UnitName <> 'ALUM'
	order by Sort

	select * from @PROVOSTCampaignList
	order by Value
end
else if @pCampaignDefaults = 'UR' 
begin
	SELECT @CurrentCampaigns = GroupNode
	FROM UDPGroups
	WHERE UnitID = 4 ;  -- get all under UA MAIN - UR 

	SELECT '(' + UnitName + ') ' + (select CampaignDescription from BBPM_DW.dbo.Dim_Campaign C where C.CampaignIdentifier = UnitName) as  Label ,
	UnitName as Value, ROW_NUMBER() OVER(order by UnitName) AS Sort
	FROM UDPGroups
	WHERE GroupNode.GetAncestor(1) = @CurrentCampaigns  and UnitName <> 'AFFAPM'
	order by Sort
end
else if @pCampaignDefaults = 'SAEM' 
begin

	SELECT @CurrentCampaigns = GroupNode
	FROM UDPGroups
	WHERE UnitID = 6 ;  -- get all under UA MAIN - SAEM 

	SELECT '(' + UnitName + ') ' + (select CampaignDescription from BBPM_DW.dbo.Dim_Campaign C where C.CampaignIdentifier = UnitName) as  Label ,
	UnitName as Value, ROW_NUMBER() OVER(order by UnitName) AS Sort
	FROM UDPGroups
	WHERE GroupNode.GetAncestor(1) = @CurrentCampaigns  and UnitName <> 'AFFUSF'
	order by Sort
end	
else if @pCampaignDefaults = 'RDI'		-- (Research)
begin
	SELECT @CurrentCampaigns = GroupNode
	FROM UDPGroups
	WHERE UnitID = 5 ;  -- get all under RDI 

	SELECT '(' + UnitName + ') ' + (select CampaignDescription from BBPM_DW.dbo.Dim_Campaign C where C.CampaignIdentifier = UnitName) as  Label ,
	UnitName as Value, ROW_NUMBER() OVER(order by UnitName) AS Sort
	FROM UDPGroups
	WHERE GroupNode.GetAncestor(1) = @CurrentCampaigns 
	order by Sort
end
else if @pCampaignDefaults = 'ICA' 
begin
	SELECT @CurrentCampaigns = GroupNode
	FROM UDPGroups
	WHERE UnitID = 3 ;  -- get all under ICA 

	SELECT '(' + UnitName + ') ' + (select CampaignDescription from BBPM_DW.dbo.Dim_Campaign C where C.CampaignIdentifier = UnitName) as  Label ,
	UnitName as Value, ROW_NUMBER() OVER(order by UnitName) AS Sort
	FROM UDPGroups
	WHERE GroupNode.GetAncestor(1) = @CurrentCampaigns 
	order by Sort
end
else if @pCampaignDefaults = 'UAF' 
begin
	SELECT @CurrentCampaigns = GroupNode
	FROM UDPGroups
	WHERE UnitID = 12 ;  -- get all under UAF 

	SELECT '(' + UnitName + ') ' + (select CampaignDescription from BBPM_DW.dbo.Dim_Campaign C where C.CampaignIdentifier = UnitName) as  Label ,
	UnitName as Value, ROW_NUMBER() OVER(order by UnitName) AS Sort
	FROM UDPGroups
	WHERE GroupNode.GetAncestor(1) = @CurrentCampaigns 
	order by Sort
end
else if @pCampaignDefaults = 'None'
begin
	SELECT '(' + CampaignIdentifier + ') ' + CampaignDescription as  Label, CampaignIdentifier AS Value, 
		ROW_NUMBER() OVER(PARTITION BY IsInactive order by CampaignIdentifier) AS Sort
	FROM [BBPM_DW].dbo.DIM_Campaign
	WHERE IsInactive = 'No'
	order by Sort
end

END