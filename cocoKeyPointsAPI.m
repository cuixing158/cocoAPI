function [allCOCOdata,cocoDatastore,keyPtsNames,skeleton] = ...
    cocoKeyPointsAPI(imagesDir,annotationFile)
% 功能：优雅的实现coco2014，coco2017数据集keypoints新接口
%
% 输入：
%     imagesDir，string类型，输入COCO图像文件根目录
%     annotationFile，string类型，与之对应的标注json文件
%
% 输出：
%     allCOCOdata， table类型，所有带有标注的完整信息，每行代表一副图像
%     cocoDatastore，TransformedDatastore object，可就地迭代对象
%     keyPtsNames，categorical类型数组，长度为17，分别为人体各个部位id顺序名字
%     skeleton，double类型数组，M*2大小，人体部位各个id连接情况，第一列与第二列id进行连接
%
% Example:
% imagesDir = './yourDataPath/coco2017/val2017/';
% annFile = './yourDataPath/coco2017/annotations_trainval2017/annotations/person_keypoints_val2017.json';
% [allCOCOdata,cocoDatastore,keyPtsNames,skeleton] = ...
%   cocoKeyPointsAPI(imagesDir,annFile)
% while cocoDatastore.hasdata()
%     data = read(cocoDatastore);
%     img = data{1};   % origin image(H×W×C)
%     bboxs = data{2}; % Bounding boxes (NumObjects x 4,  arranged as [x y w h])
%     masks = data{3}; % Masks (H x W x NumObjects)
%     keyPts = data{4}; % KeyPoints (17×3×NumObjects)
%     ...
% end
%
% MATLAB R2020b or higher, only support "person" keypoints category
% author:cuixingxing
% email: cuixingxing150@gmail.com
% 2021.8.10 create
%
arguments
    imagesDir (1,1) string % coco2014/2017 images root directory
    annotationFile (1,1) string % annotation json file
end

%% read json file
str = fileread(annotationFile);
data = jsondecode(str); % takes a little time
imagesTable = struct2table(data.images);
allAnnotations = struct2table(data.annotations);
keyPtsNames = categorical(data.categories.keypoints);
skeleton = data.categories.skeleton;

%% preprocess table type
imagesTable = renamevars(imagesTable,'id','image_id');
imagesTable = movevars(imagesTable,'image_id','Before','license');
imagesTable = sortrows(imagesTable,'image_id');
allAnnotations(allAnnotations.iscrowd==1,:)=[]; %remove no keypoints ann
allAnnotations(allAnnotations.num_keypoints==0,:)=[];%remove no keypoints ann
allAnnotations = removevars(allAnnotations,{'area','id',...
    'num_keypoints','category_id','iscrowd'});
allAnnotations = sortrows(allAnnotations,'image_id');
allGroupAnnotations = rowfun(@groupFcn,allAnnotations,... % or findgroups/splitapply
    'GroupingVariable','image_id',...
    'OutputVariableName',["segments","bbox","keypoints"]);

% remove unlabeled images
imagesTable(~ismember(imagesTable.image_id,allGroupAnnotations.image_id),:)=[];
assert(all(imagesTable.image_id==allGroupAnnotations.image_id));
allCOCOdata = [imagesTable,allGroupAnnotations(:,2:end)];

% or costum define your datastore
arrds = arrayDatastore(allCOCOdata,"ReadSize",1);
cocoDatastore = transform(arrds,@(x)decodeCOCO(x,imagesDir));
end

%% support function
function outputdata = decodeCOCO(input,imagesDir)
data = input{1};
oriImg = imread(fullfile(imagesDir,data.file_name{1}));
bboxs = data.bbox{1};
bboxs(:,1:2) = bboxs(:,1:2)+1;

segments = data.segments{1};
masks = false(data.height, data.width, length(segments));
for i = 1:length(segments)
    mask = false(data.height, data.width);
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
    
    masks(:,:,i) = mask;
end

keypoints = data.keypoints{1};
bias = ones(size(keypoints));
bias(:,3,:)=0;
keypoints = keypoints+bias;% x,y plus one

outputdata{1} =oriImg;
outputdata{2} =bboxs;
outputdata{3} =masks;
outputdata{4} =keypoints;
end

function [segments,bbox,keypoints] = groupFcn(segmentation,keypoints,bbox)
segments = {segmentation};
bbox = {reshape(cat(1,bbox{:}),4,[])'};
keypoints = reshape(cat(1,keypoints{:}),3,17,[]);
keypoints = permute(keypoints,[2,1,3]);% 17*3*NumObjects
keypoints = {keypoints};
end

