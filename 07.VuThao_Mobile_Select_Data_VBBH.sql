USE FPTPetro_DataeOffice
GO

IF OBJECT_ID('VuThao_Mobile_Select_Data_VBBH', 'P') IS NOT NULL DROP PROCEDURE VuThao_Mobile_Select_Data_VBBH
GO

CREATE PROCEDURE [dbo].[VuThao_Mobile_Select_Data_VBBH]
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

	IF ISNULL(@Parameters,'') != ''
	BEGIN
		DECLARE @tbl@Parameters TABLE(ParentID INT, [Key] NVARCHAR(100), [Value] NVARCHAR(MAX))
		INSERT INTO @tbl@Parameters 
		SELECT Parent_ID,[Name],StringValue FROM parseJSON(@Parameters) WHERE ISNULL([Name],'-') != '-'
	END

	DECLARE @tblVBBH TABLE (
			[ID] BIGINT,
			[Title] NVARCHAR(150),
			[TrangThai] NVARCHAR(100),
			[DoKhan] NVARCHAR(50),
			[DoMat] NVARCHAR(50),
			[DonVi] NVARCHAR(MAX),
			[NguoiSoanThaoText] NVARCHAR(255),
			[DocumentType] NVARCHAR(255),
			[ReceivedDate] DATE,
			[NguoiKyVanBanText] NVARCHAR(255),
			[ChucVu] NVARCHAR(255),
			[DonViSoanThao] NVARCHAR(255),
			[SoVanBan] NVARCHAR(255),
			[TrichYeu] NVARCHAR(4000),
			[YKienLanhDao] NVARCHAR(MAX),
			[LTDonVi] NVARCHAR(MAX),
			[CodeItemId] BIGINT,
			[DocSignType] TINYINT,
			[SignDate] DATETIME,
			[Created] DATETIME,
			[AuthorText] NVARCHAR(255),
			[ImagePath] NVARCHAR(255),
			[Position] NVARCHAR(125)
		)

	DECLARE @DomainUrl VARCHAR(250)
	DECLARE @SiteVBUrl VARCHAR(255)
	DECLARE @DBName VARCHAR(150) = (SELECT TOP 1 [VALUE] FROM Settings WHERE [KEY] = 'DBSite')
	DECLARE @FromDate DATETIME = NULL
	DECLARE @ToDate DATETIME = NULL
	DECLARE @FromDateF DATETIME = NULL
	DECLARE @ToDateF DATETIME = NULL
	DECLARE @FilterText NVARCHAR(MAX) = NULL
	DECLARE @TinhTrang NVARCHAR(MAX) = NULL
	DECLARE @BanLanhDao NVARCHAR(MAX) = NULL
	DECLARE @LIMIT INT = 0, @OFFSET INT = 0, @STATUS INT = 0, @IsCount INT = 0, @ModuleId VARCHAR(50) = NULL

	SET @DomainUrl =(SELECT TOP 1 [VALUE] FROM Settings WHERE [KEY] = 'DomainUrl')
	SET @SiteVBUrl = CONCAT(@DomainUrl,IIF(@CurrentSite = N'', N'', N'/' + @CurrentSite))
	SET @SiteVBUrl = CONCAT(@SiteVBUrl,'/vanban')

	IF (SELECT MAX(ParentID) FROM @tbl@Parameters GROUP BY ParentID) = 1
	BEGIN
		SELECT @LIMIT = Limit, @OFFSET = Offset, @STATUS = Status, @IsCount = IsCount
			, @ModuleId = IIF(ISNULL(ModuleId,'') = '', NULL , ModuleId)
			, @FromDate = IIF(ISNULL(FromDate,'') = '', NULL , FromDate)
			, @ToDate = IIF(ISNULL(ToDate,'') = '', NULL , ToDate)
			, @FilterText = IIF(ISNULL(FilterText,'') = '', NULL , FilterText)
			, @BanLanhDao = IIF(ISNULL(BanLanhDao,'') = '', NULL , BanLanhDao)
			, @TinhTrang = IIF(ISNULL(TinhTrang,'') = '', NULL , TinhTrang)
		FROM @tbl@Parameters SRC
		PIVOT(MAX([Value]) FOR [Key] IN (Limit,Offset,Status,IsCount,ModuleId,FromDate,ToDate,FilterText,BanLanhDao,TinhTrang)) PIV;
	END

	IF @FromDate IS NOT NULL
		SET @FromDateF = [dbo].fnFormatDate(@FromDate,'YYYY/MM/DD HH:MI:SS');

	IF @ToDate IS NOT NULL
	BEGIN
		SET @ToDate = CONVERT(VARCHAR,@ToDate,111) + ' 23:59:59'
		SET @ToDateF = [dbo].fnFormatDate(@ToDate,'YYYY/MM/DD HH:MI:SS');
	END

	DECLARE @IsAdmin BIT = 0

	SET @cmd = N'SET @IsAdmin = ISNULL((SELECT TOP 1 1 FROM [' + @DBName + @CurrentSite + N']..[Group] G
		WHERE G.Title = N''Admin''
		AND EXISTS(SELECT TOP 1 1 FROM [' + @DBName + @CurrentSite + N']..UserInGroup UG WHERE UG.GroupId = G.ID AND UG.UserId = @UserId)
		),0)'

	EXECUTE sp_executesql   @cmd,
							N'@UserId VARCHAR(50),@IsAdmin BIT OUT ',
							@UserId = @UserId,@IsAdmin = @IsAdmin OUT

	IF ISNULL(@IsAdmin, 0) = 0
	BEGIN
		SET @cmd = N'SET @IsAdmin = ISNULL(
			(SELECT TOP 1 1 FROM [' + @DBName + N'].PLX.ResoureGroup NOLOCK
			WHERE ModuleId IN (6,8)
			AND (UserId = @UserId OR UserId LIKE CONCAT(''%'',@UserId,''%''))
			),0)'

		EXECUTE sp_executesql   @cmd,
								N'@UserId VARCHAR(50),@IsAdmin BIT OUT ',
								@UserId = @UserId,@IsAdmin = @IsAdmin OUT
	END
	
	SET @cmd = N'
				DECLARE @DocId TABLE(ID BIGINT, PRIMARY KEY (ID DESC));
				DECLARE @UserTable TABLE(ID uniqueidentifier,PRIMARY KEY (ID));

				IF ISNULL(@IsAdmin, 0) = 0
				BEGIN
					INSERT INTO @UserTable ([ID]) VALUES(@UserId)

					INSERT INTO @UserTable SELECT [GroupId] FROM ['+@DBName + @CurrentSite +N'].[dbo].[UserInGroup] WITH (NOLOCK) WHERE [UserId] = @UserId

					INSERT INTO @DocId
					SELECT DISTINCT [VBId] 
					FROM ['+@DBName + @CurrentSite +N']..[VanBanBanHanhPermission] VBP (NOLOCK)
					WHERE EXISTS(SELECT TOP 1 1 FROM @UserTable U WHERE U.ID = VBP.UserId)
				END

				SELECT  VBBH.[ID],VBBH.[Title],VBBH.[TrangThai],VBBH.[DoKhan],VBBH.[DoMat],VBBH.[DonVi],VBBH.[NguoiSoanThaoText],VBBH.[DocumentType]
						,VBBH.[ReceivedDate],VBBH.[NguoiKyVanBanText],VBBH.[ChucVu],VBBH.[DonViSoanThao],VBBH.[SoVanBan],VBBH.[TrichYeu],VBBH.[YKienLanhDao]
						,VBBH.[LTDonVi],VBBH.[CodeItemId],VBBH.[DocSignType],VBBH.[SignDate],VBBH.[Created]
						,PP.FullName AS AuthorText
						, PP.ImagePath, PP.Position
				FROM ['+@DBName + @CurrentSite +N']..VanBanBanHanh VBBH (NOLOCK)
				LEFT JOIN ['+@DBName + @CurrentSite +N']..PersonalProfile PP (NOLOCK) ON PP.ID = VBBH.CreatedBy
				WHERE (@IsAdmin=1 OR @UserId IS NULL OR EXISTS(SELECT TOP 1 1 FROM @DocId D WHERE D.ID = VBBH.ID))
					AND VBBH.TrangThai = N''Phát hành'' 
					AND VBBH.TrangThai != N''Thu hồi''	
				'

	IF @FromDateF IS NOT NULL AND @ToDateF IS NOT NULL
		SET @cmd = @cmd + N' AND VBBH.Created BETWEEN @FromDateF AND @ToDateF'

	IF @FilterText IS NOT NULL
		SET @cmd = @cmd + N' AND (VBBH.TrichYeu LIKE N''%' + @FilterText + '%'') '

	INSERT INTO @tblVBBH
	EXECUTE sp_executesql @cmd,
							N'@Email NVARCHAR(200), @SiteVBUrl VARCHAR(255), @STATUS INT, @FromDateF DATETIME, @ToDateF DATETIME,@IsAdmin BIT,@UserId VARCHAR(50)',
							@Email = @Email, @SiteVBUrl = @SiteVBUrl, @STATUS = @STATUS, @FromDateF = @FromDateF, @ToDateF = @ToDateF,@IsAdmin = @IsAdmin,@UserId = @UserId

	IF @LIMIT > 0 AND @IsCount = 0
	BEGIN
		SELECT * 
		FROM @tblVBBH
		--WHERE (@ModuleId IS NULL OR EXISTS (SELECT 1 FROM dbo.Split(@ModuleId,',') WHERE Item = ModuleId))
		ORDER BY ISNULL(ReceivedDate,Created) DESC,Title DESC
		OFFSET @OFFSET ROWS FETCH NEXT @LIMIT ROWS ONLY
	END

	SELECT COUNT(1) AS totalRecord FROM @tblVBBH --WHERE (@ModuleId IS NULL OR EXISTS (SELECT 1 FROM dbo.Split(@ModuleId,',') WHERE Item = ModuleId))
END