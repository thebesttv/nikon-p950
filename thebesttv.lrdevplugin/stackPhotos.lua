-- local LrDialogs = import 'LrDialogs'
-- LrDialogs.message("Hello World")

local LrLogger = import 'LrLogger'
local logger = LrLogger('Main')
logger:enable("logfile")
local log = logger:quickf('info')

-- log("can you see this log?")

local LrApplication = import 'LrApplication'
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'
local LrView = import 'LrView'
local LrFileUtils = import 'LrFileUtils'
local LrBinding = import 'LrBinding'
local LrFunctionContext = import 'LrFunctionContext'

-- 获取所有选中source中的照片并去重
local function getUniquePhotosFromSources(sources)
  local allPhotosSet = {}
  local allPhotos = {}

  for _, source in ipairs(sources) do
    local photosInSource = source:getPhotos()
    for _, photo in ipairs(photosInSource) do
      local photoId = photo.localIdentifier -- 使用照片的唯一标识符去重
      if not allPhotosSet[photoId] then
        allPhotosSet[photoId] = true
        table.insert(allPhotos, photo)
      end
    end
  end

  return allPhotos
end

-- 过滤出非 jpg 或 nrw 的照片
local function filterNonCameraGeneratedPhotos(allPhotos)
  local nonCameraGenerated = {}

  for _, photo in ipairs(allPhotos) do
    local fileName = photo:getFormattedMetadata("fileName")
    local extension = string.lower(fileName:match("^.+%.(.+)$") or "")

    -- 如果文件扩展名不是 jpg 或 nrw，则添加到数组中
    if extension ~= "jpg" and extension ~= "nrw" then
      table.insert(nonCameraGenerated, photo)
    end
  end

  return nonCameraGenerated
end

-- 添加表格行的函数，支持可选字体参数
local function addTableRow(contents, viewFactory, leftText, rightText, font)
  table.insert(contents, viewFactory:row {
    viewFactory:static_text {
      title = leftText,
      font = font or "<system>",
      alignment = "left",
      fill_horizontal = 1,
    },
    viewFactory:static_text {
      title = rightText,
      font = font or "<system>",
      alignment = "right",
    },
  })
end

-- 为每个source添加表格行
local function addSourceRowsToContents(contents, sources, viewFactory)
  for i, source in ipairs(sources) do
    local sourcePath = source:getPath()
    local photosInSource = source:getPhotos()
    local photoCount = #photosInSource

    -- 添加每个source的行
    addTableRow(contents, viewFactory, string.format("%s", sourcePath), tostring(photoCount))
  end
end

-- 检查各个磁盘中是否存在文件NCFL/NCCONLST.LST，并返回第一个找到的文件路径
local function checkForFileInDrives()
  local drives = {"D", "E", "F"} -- C盘没必要查找
  for _, drive in ipairs(drives) do
    local filePath = drive .. ":/NCFL/NCCONLST.LST"
    if LrFileUtils.exists(filePath) then
      return filePath -- 返回找到的第一个文件路径
    end
  end
  return nil
end

local function updateActionButton(properties)
  local fileName = properties.ncconlst:match("[^\\/]+$")
  properties.actionEnabled = (fileName == "NCCONLST.LST")
end

LrTasks.startAsyncTask(function ()
  local catalog = LrApplication.activeCatalog()

  -- 获取当前显示的文件夹
  local activeSources = catalog:getActiveSources()
  if #activeSources == 0 then
    LrDialogs.message("Folder Information", "No active folder selected")
    return
  end

  -- 获取去重后的所有照片
  local allPhotos = getUniquePhotosFromSources(activeSources)

  -- 过滤出非拍摄生成的照片
  local nonCameraGenerated = filterNonCameraGeneratedPhotos(allPhotos)

  LrFunctionContext.callWithContext('GetFileName', function( context )

    -- 创建LrView工厂对象
    local f = LrView.osFactory()
    local bind = LrView.bind

    -- 创建表格布局
    local contents = {}
    -- 添加标题行，使用加粗字体
    addTableRow(contents, f, "Source Folder", "#Photos", "<system/bold>")

    -- 添加每个source的行
    addSourceRowsToContents(contents, activeSources, f)

    -- 在表格末尾添加一行，显示去重后的照片总数，使用加粗字体
    addTableRow(contents, f, "Total unique photos", tostring(#allPhotos), "<system/bold>")

    -- 添加非拍摄生成的照片数量行
    addTableRow(contents, f, "Non-camera generated photos", tostring(#nonCameraGenerated), "<system/bold>")

    -- 如果有非拍摄生成的照片，列出前五个文件名
    if #nonCameraGenerated > 0 then
      addTableRow(contents, f, "First 5 non-camera generated:", "", "<system/bold>")
      for i = 1, math.min(5, #nonCameraGenerated) do
        local fileName = nonCameraGenerated[i]:getFormattedMetadata("fileName")
        addTableRow(contents, f, fileName, "", "<system>")
      end
      addTableRow(contents, f, "Can't be applied to non-camera generated sets!!!", "", "<system/bold>")
    end

    -- properties 用于 bind() 相关
    local properties = LrBinding.makePropertyTable(context)
    properties.ncconlst = checkForFileInDrives() or ""
    properties.actionEnabled = false  -- 用于控制OK按钮的启用状态
    updateActionButton(properties)

    -- 如果所有照片都是拍摄生成的，准备堆叠连拍照片
    if #nonCameraGenerated == 0 then
      addTableRow(contents, f, "Default NCFL/NCCONLST.LST:", properties.ncconlst, "<system/bold>")

      table.insert(contents, f:row {
        f:static_text {
          title = "Selected file:",
        },
        f:edit_field {
          value = LrView.bind("ncconlst"),
          width_in_chars = 30,
          enabled = false,
        },
        f:push_button {
          title = "Select File",
          action = function()
            -- 文件选择对话框
            local file = LrDialogs.runOpenPanel({
              title = "Select a File",
              canChooseFiles = true,
              canChooseDirectories = false,
              allowsMultipleSelection = false,
            })

            if file then
              local selectedFileName = file[1]:match("[^\\/]+$")  -- 获取文件名
              if selectedFileName == "NCCONLST.LST" then
                properties.ncconlst = file[1]  -- 更新绑定的值
                updateActionButton(properties)
              else
                -- 文件名不匹配时，弹出错误框
                LrDialogs.message("Error", "Please select the NCCONLST.LST file.", "critical")
              end
            end

          end
        }
      })

      table.insert(contents, f:row {
        f:push_button {
          title = "Run",
          action = function()
            -- OK按钮的行为
            LrDialogs.message("File Selected", properties.ncconlst, "info")
          end,
          enabled = LrView.bind("actionEnabled"), -- 绑定按钮的启用状态
        },
      })
    end

    -- 将contents表中的UI元素放入到一个column布局中
    local c = f:column {
      bind_to_object = properties,
      spacing = f:control_spacing(),
      unpack(contents), -- 解包contents表以将其作为子元素
    }

    -- 显示自定义对话框
    -- LrDialogs.presentFloatingDialog(_PLUGIN, {
    --   title = "Source Information",
    --   contents = c,
    --   resizable = true,
    -- })
    LrDialogs.presentModalDialog {
      title = "Source Information",
      contents = c,
      resizable = false,
      cancelVerb = "< exclude >"
    }
  end)

end)
