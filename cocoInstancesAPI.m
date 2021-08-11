function [allCOCOdata,cocoDatastore,cocoNames] = cocoInstancesAPI(imagesDir,annotationFile,categoryNames)
% 功能：优雅的实现coco2014，coco2017数据集Instances新接口
% 
% 输入：
%     imagesDir，string类型，输入COCO图像文件根目录
%     annotationFile，string类型，与之对应的标注json文件
%     categoryNames，string类型，1*N大小，物体类别，默认所有类别
% 输出：
%     allCOCOdata， table类型，所有带有标注的完整信息，每行代表一副图像
%     cocoDatastore，TransformedDatastore object，可就地迭代对象
%     cocoNames，categorical类型，80个类别
%
% Example:
% imagesDir = './yourDataPath/coco2017/val2017/';
% annFile = './yourDataPath/coco2017/annotations_trainval2017/annotations/instances_val2017.json';
% [allCOCOdata,cocoDatastore,cocoNames] = cocoAPI(imagesDir,annFile)
% while cocoDatastore.hasdata()
%     data = read(cocoDatastore);
%     img = data{1};   % origin image(H×W×C)
%     bboxs = data{2}; % Bounding boxes (NumObjects x 4,  arranged as [x y w h])
%     labels = data{3};% Labels (NumObjects x 1), categorical
%     masks = data{4}; % Masks (H x W x NumObjects) 
%     ...
% end
%
% MATLAB R2020b or higher
% author:cuixingxing
% email: cuixingxing150@gmail.com
% 2021.8.6 create
%
arguments
    imagesDir (1,1) string % coco2014/2017 images root directory
    annotationFile (1,1) string % annotation json file
    categoryNames  (1,:) string = "all"
end

%% read json file
str = fileread(annotationFile);
data = jsondecode(str); % takes a little time
imagesTable = struct2table(data.images);
allAnnotations = struct2table(data.annotations);
coconamesT = struct2table(data.categories);
cocoNames = categorical(coconamesT.name(:));
category_id = coconamesT.id;

% filter classes
if any(categoryNames~="all")
    categoryNames = categorical(categoryNames);
    try
        idxs = arrayfun(@(x)find(x==cocoNames),categoryNames);
    catch
        error("The third input parameter 'categoryNames' must be the name in cocoNames:"+...
            strjoin(string(cocoNames),','));
    end
    catIds = category_id(idxs);
    selectAnnIdxs = ismember(allAnnotations.category_id,catIds);
    allAnnotations = allAnnotations(selectAnnIdxs,:);
end

%% preprocess table type
imagesTable = renamevars(imagesTable,'id','image_id');
imagesTable = movevars(imagesTable,'image_id','Before','license');
imagesTable = sortrows(imagesTable,'image_id');
allAnnotations = removevars(allAnnotations,{'area','id'});
allGroupAnnotations = rowfun(@groupFcn,allAnnotations,... % or findgroups/splitapply
    'GroupingVariable','image_id',...
    'OutputVariableName',["segments","iscrowd","bbox","category_id"]);

% remove unlabeled images
imagesTable(~ismember(imagesTable.image_id,allGroupAnnotations.image_id),:)=[];
assert(all(imagesTable.image_id==allGroupAnnotations.image_id));
allCOCOdata = [imagesTable,allGroupAnnotations(:,2:end)];

% or costum define your datastore
arrds = arrayDatastore(allCOCOdata,"ReadSize",1);
cocoDatastore = transform(arrds,@(x)decodeCOCO(x,category_id,cocoNames,imagesDir));
end

%% support function
function outputdata = decodeCOCO(input,category_id,cocoNames,imagesDir)
data = input{1};
oriImg = imread(fullfile(imagesDir,data.file_name{1}));
bboxs = data.bbox{1};
bboxs(:,1:2) = bboxs(:,1:2)+1;

catIdx = data.category_id{1};
cocoIdx = arrayfun(@(v)find(v==category_id),catIdx);
labels = cocoNames(cocoIdx);

segments = data.segments{1};
iscrowd = data.iscrowd{1};
masks = false(data.height, data.width, length(labels));
for i = 1:length(labels)
    mask = false(data.height, data.width);
    if iscrowd(i) % RLE算法,Run Length Encoding（行程长度压缩算法）
        seg = segments{i};% struct type
        counts = seg.counts;
        encodeMode = false(length(counts),1);
        encodeMode(2:2:end)=true;
        mask = repelem(encodeMode,counts);
        mask = reshape(mask,[data.height, data.width]);
    else
        seg = segments{i};
        if ~isempty(seg)
            if iscell(seg)
                for j = 1:length(seg)
                    subseg = seg{j};
                    x = subseg(1:2:end)+1;
                    y = subseg(2:2:end)+1;
                    mask = mask | poly2mask(x,y,data.height, data.width);
                end
            else
                x = seg(1:2:end)+1;
                y = seg(2:2:end)+1;
                mask = poly2mask(x,y,data.height, data.width);
            end
        end
    end
    masks(:,:,i) = mask;
end
outputdata{1} =oriImg;
outputdata{2} =bboxs;
outputdata{3} =labels;
outputdata{4} =masks;
end

function [segments,iscrowd,bbox,category_id] = groupFcn(segmentation,...
    iscrowd,bbox,category_id)
segments = {segmentation};
iscrowd = {iscrowd(:)};
bbox = {reshape(cat(1,bbox{:}),4,[])'};
category_id = {category_id(:)};
end