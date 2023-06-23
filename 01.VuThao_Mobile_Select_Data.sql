USE Petrolimex_DataeOffice
GO 

IF OBJECT_ID('VuThao_Mobile_Select_Data', 'P') IS NOT NULL DROP PROCEDURE VuThao_Mobile_Select_Data
GO

CREATE PROCEDURE [dbo].[VuThao_Mobile_Select_Data]
	@Action VARCHAR(100) = '',
	@UserId VARCHAR(50) = '',
	@Email NVARCHAR(200) = '',
	@CurrentSite VARCHAR(100) = '',
	@Parameters NVARCHAR(MAX) = ''
AS
BEGIN
	SET NOCOUNT ON;

	IF ISNULL(@Action,'') = ''
		RETURN;

	DECLARE @cmd NVARCHAR(MAX) = N''
	DECLARE @storeName NVARCHAR(MAX) = N''

	IF @Action = 'DanhMuc'
		SET @storeName = N'[VuThao_Mobile_Select_Data_DanhMuc]'
	ELSE IF @Action = 'ProcessingNotify' OR @Action = 'PhoiHop' OR @Action = 'TCThongBao' OR @Action = 'VBDenThongBao' OR @Action = 'VBDiThongBao'OR @Action = 'VBDenTitle'OR @Action = 'VBDiTitle'
		SET @storeName = N'[VuThao_Mobile_Select_Data_Home]'
	ELSE IF @Action = 'VBDenChoChoYKien' OR @Action = 'VBDenDaGiaiQuyet' OR @Action = 'VBDenChoThucHien' OR @Action = 'VBDenTatCa'
		SET @storeName = N'[VuThao_Mobile_Select_Data_VBDen]'
	ELSE IF @Action = 'VBDiChoPheDuyet' OR @Action = 'VBDiDaPheDuyet' OR @Action = 'VBDiTatCa'
		SET @storeName = N'[VuThao_Mobile_Select_Data_VBDi]'
	ELSE IF @Action = 'VBDiDaPhatHanh'
		SET @storeName = N'[VuThao_Mobile_Select_Data_VBBH]'
	ELSE IF @Action = 'VBDenUserShare' OR @Action = 'VBGetViewer' OR @Action = 'VBDenGetWorkflowHistory' 
		OR @Action = 'VBDenTaskJson' OR @Action = 'VBBHTaskJson'
		OR @Action = 'VBDiGetWorkflowHistory' OR @Action = 'VBDiUserShare' OR @Action = 'VBBHUserShare' OR @Action = 'GetNotifyById'
		OR @Action = 'VBBHGetWorkflowHistory' OR @Action = 'VBBHTaskById' OR @Action = 'VBBHTaskByIdUserRole' OR @Action = 'VBDenTaskById'
		OR @Action = 'VBTaskByIdUserRole' OR @Action = 'UpdateNotifyAsRead'
		SET @storeName = N'[VuThao_Mobile_Select_Data_Action]'

	IF @storeName != N''
	BEGIN
		SET @cmd = N'EXEC ' + @storeName + N' @Action = @Action, @UserId = @UserId, @Email = @Email, @CurrentSite = @CurrentSite, @Parameters = @Parameters'
		Print @cmd
		EXECUTE sp_executesql @cmd,
						N'@Action VARCHAR(100), @UserId VARCHAR(50), @Email NVARCHAR(200), @CurrentSite VARCHAR(100), @Parameters NVARCHAR(MAX)',
						@Action = @Action,
						@UserId = @UserId,
						@Email = @Email,
						@CurrentSite = @CurrentSite,
						@Parameters = @Parameters
	END
END