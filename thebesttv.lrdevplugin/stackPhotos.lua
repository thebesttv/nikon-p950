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

local LrXml = import "LrXml"

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

-- 添加一行，有bind和transform
local function addTableLineWithBind(contents, viewFactory, prefix, bindKey, font)
  addTableRow(contents, viewFactory, LrView.bind {
      key = bindKey,
      transform = function(value, fromTable)
        return prefix .. (value or "")
      end },
    "", font)
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
  local drives = { "D", "E", "F" } -- C盘没必要查找
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

-- 读取并解析XML
local function parseXml(filename)
  local content = LrFileUtils.readFile(filename)

  -- 使用LrXml解析XML字符串
  local xmlDom = LrXml.parseXml(content)

  if not xmlDom then
    log("无法解析XML文件: " .. filename)
  end

  return xmlDom
end

local function fileNameFromPath(path)
  return path:match("[^\\/]+$")
end

-- 解析照片名，例如 DSCN1234.NRW -> DSCN, 1234, NRW
local function parsePhotoName(photoName)
  local prefix, number, extension = photoName:match("^(%a+)(%d+)%.(%a+)$")
  if not prefix or not number or not extension then
    LrDialogs.message("Error", "Invalid photo name: " .. photoName, "critical")
  end
  return prefix, tonumber(number), extension
end

-- 处理XML DOM对象
local function processNCCONLST(xmlDom, properties)
  local header = xmlDom:childAtIndex(1)
  local modelName = header:childAtIndex(3):text()
  properties.modelName = modelName

  local rengroup = xmlDom:childAtIndex(2)

  local groupTotal = rengroup:childAtIndex(1):text()
  groupTotal = tonumber(groupTotal)
  properties.groupTotal = groupTotal

  local groupList = rengroup:childAtIndex(2)
  -- items: (table, default: nil) Table of items to be displayed. Each entry has a localizeable title and a value.
  local groupItems = {}
  -- 遍历每个group
  for i = 1, groupList:childCount() do
    local group = groupList:childAtIndex(i)
    local groupNumber = tonumber(group:childAtIndex(1):text())
    local groupCount = tonumber(group:childAtIndex(2):text())
    local groupFlag = group:childAtIndex(3) -- 未使用

    local firstPic = group:childAtIndex(4):text()
    local lastPic = group:childAtIndex(5):text()
    local displayPic = group:childAtIndex(6):text()

    firstPic = fileNameFromPath(firstPic)
    lastPic = fileNameFromPath(lastPic)
    displayPic = fileNameFromPath(displayPic)

    local _, firstNumber, _ = parsePhotoName(firstPic)
    local _, lastNumber, _ = parsePhotoName(lastPic)
    local _, displayNumber, _ = parsePhotoName(displayPic)

    table.insert(groupItems, {
      groupNumber = groupNumber,
      groupCount = groupCount,
      firstNumber = firstNumber,
      lastNumber = lastNumber,
      displayNumber = displayNumber,
      -- for simple_list
      title = string.format(
        "%3d: %2d photos, %s - %s, display: %s",
        groupNumber, groupCount, firstPic, lastPic, displayPic),
      value = groupNumber
    })
  end
  properties.groupList = groupItems
end

local function checkNonCameraGeneratedPhotos(contents, f, allPhotos)
  -- 过滤出非拍摄生成的照片
  local nonCameraGenerated = filterNonCameraGeneratedPhotos(allPhotos)

  if #nonCameraGenerated == 0 then
    return false
  end

  -- 添加非拍摄生成的照片数量行
  addTableRow(contents, f, "Non-camera generated photos", tostring(#nonCameraGenerated), "<system/bold>")

  local items = {}
  local maxChars = 0
  for i = 1, #nonCameraGenerated do
    local fileName = nonCameraGenerated[i]:getFormattedMetadata("fileName")
    local path = nonCameraGenerated[i]:getRawMetadata("path")

    local line = fileName .. "\t" .. path
    table.insert(items, line)
    maxChars = math.max(maxChars, #line)
  end

  table.insert(contents, f:scrolled_view {
    height = 200,
    width = 500,
    f:static_text {
      title = table.concat(items, "\n"),
      width_in_chars = math.max(50, maxChars),
      height_in_lines = #items,
    },
  })

  LrDialogs.message("Error", "Can't be applied to non-camera generated sets!", "critical")

  return true
end

local function checkDuplicatePhotoNames(contents, f, allPhotos)
  local photoOfName = {} -- number -> photo
  for _, photo in ipairs(allPhotos) do
    local fileName = photo:getFormattedMetadata("fileName")
    local _, number, _ = parsePhotoName(fileName)
    log(fileName .. " " .. number)
    if photoOfName[number] then
      local anotherPhoto = photoOfName[number]
      local anotherFileName = anotherPhoto:getFormattedMetadata("fileName")
      addTableRow(contents, f,
        "Duplicate photo name: " .. anotherFileName .. " & " .. fileName,
        "", "<system/bold>")
      return photoOfName, false
    end
    photoOfName[number] = photo
  end
  return photoOfName, true
end

-- 返回 firstPic 和 lastPic 之间的照片。如果 displayPic 存在，它会是第一张照片
local function getPhotosWithinRange(photoOfName, firstNumber, lastNumber, displayNumber)
  local photos = {}

  local photo = photoOfName[displayNumber]
  if photo then
    table.insert(photos, photo)
  end

  for i = firstNumber, lastNumber do
    if i ~= displayNumber then
      local photo = photoOfName[i]
      if photo then
        table.insert(photos, photo)
      end
    end
  end

  return photos
end

local function buildGUI(f, properties)
  -- 创建表格布局
  local contents = {}

  -- 获取当前选中的文件夹
  local catalog = LrApplication.activeCatalog()
  local activeFolders = {}
  -- 从当前选中的source中过滤出文件夹
  for _, source in ipairs(catalog:getActiveSources()) do
    if source:type() == "LrFolder" then
      table.insert(activeFolders, source)
    end
  end

  if #activeFolders == 0 then
    LrDialogs.message("Error", "Please select at least one folder.", "critical")
    return contents
  end

  -- 获取去重后的所有照片
  local allPhotos = getUniquePhotosFromSources(activeFolders)

  -- 添加标题行，使用加粗字体
  addTableRow(contents, f, "Source Folder", "#Photos", "<system/bold>")

  -- 添加每个source的行
  addSourceRowsToContents(contents, activeFolders, f)

  -- 在表格末尾添加一行，显示去重后的照片总数，使用加粗字体
  addTableRow(contents, f, "Total unique photos", tostring(#allPhotos), "<system/bold>")

  -- 如果有非拍摄生成的照片，列出这些照片
  if checkNonCameraGeneratedPhotos(contents, f, allPhotos) then
    return contents
  end

  -- 检查是否有重复的照片计数
  local photoOfName, ok = checkDuplicatePhotoNames(contents, f, allPhotos)
  if not ok then
    return contents
  end

  -- 所有照片都是拍摄生成的，准备堆叠连拍照片
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
          local selectedFileName = file[1]:match("[^\\/]+$") -- 获取文件名
          if selectedFileName == "NCCONLST.LST" then
            properties.ncconlst = file[1]                    -- 更新绑定的值
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
      title = "Read NCCONLST.LST",
      action = function()
        local xmlDom = parseXml(properties.ncconlst)
        processNCCONLST(xmlDom, properties)
      end,
      enabled = LrView.bind("actionEnabled"), -- 绑定按钮的启用状态
    },
    f:push_button {
      title = "Select",
      action = function()
        -- 遍历 groupList，看哪些在 photoOfName 中
        for _, group in ipairs(properties.groupList) do
          local firstNumber = group.firstNumber
          local lastNumber = group.lastNumber
          local displayNumber = group.displayNumber

          local photos = getPhotosWithinRange(photoOfName, firstNumber, lastNumber, displayNumber)
          if #photos > 0 then
            -- 选中第一张和其余的
            catalog:setSelectedPhotos(photos[1], photos)
          end
        end
      end,
      enabled = true, -- 绑定按钮的启用状态
    },
  })

  -- 解析后的NCCONLST.LST文件内容
  addTableRow(contents, f, "NCCONLST.LST Contents:", "", "<system/bold>")
  addTableLineWithBind(contents, f, "Model Name: ", "modelName", "<system>")
  -- 连拍总数
  addTableLineWithBind(contents, f, "Group Total: ", "groupTotal", "<system>")
  table.insert(contents, f:simple_list {
    title = "Group List",
    items = LrView.bind("groupList"),
    height = 200,
    width = 500,
    fill_horizontal = 1,
  })

  return contents
end

LrTasks.startAsyncTask(function()
  LrFunctionContext.callWithContext('main context', function(context)
    -- 创建LrView工厂对象
    local f = LrView.osFactory()

    -- properties 用于 bind() 相关
    local properties = LrBinding.makePropertyTable(context)
    properties.ncconlst = checkForFileInDrives() or "D:\\nikon-0921\\NCFL\\NCCONLST.LST"
    properties.actionEnabled = false -- 用于控制OK按钮的启用状态
    updateActionButton(properties)
    properties.modelName = nil
    properties.groupTotal = nil
    properties.groupList = nil

    local contents = buildGUI(f, properties)

    if #contents == 0 then
      return
    end

    -- 将contents表中的UI元素放入到一个column布局中
    local c = f:column {
      bind_to_object = properties,
      fill = 1,
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
      resizable = true,
      cancelVerb = "< exclude >"
    }
  end)
end)
