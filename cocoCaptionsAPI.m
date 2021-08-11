function [allCOCOdata,cocoDatastore] = cocoCaptionsAPI(imagesDir,annotationFile)
% 功能：优雅的实现coco2014，coco2017数据集Captions新接口
%
% 输入：
%     imagesDir，string类型，输入COCO图像文件根目录
%     annotationFile，string类型，与之对应的标注json文件
%
% 输出：
%     allCOCOdata， table类型，所有带有标注的完整信息，每行代表一副图像
%     cocoDatastore，TransformedDatastore object，可就地迭代对象
%
% Example:
% imagesDir = './yourDataPath/coco2017/val2017/';
% annFile = './yourDataPath/coco2017/annotations_trainval2017/annotations/captions_val2017.json';
% [allCOCOdata,cocoDatastore] = cocoCaptionsAPI(imagesDir,annFile)
% while cocoDatastore.hasdata()
%     data = read(cocoDatastore);
%     img = data{1};   % origin image(H×W×C)
%     captions = data{2}; % captions (NumSentences x 1 cell array)
%     ...
% end
%
% MATLAB R2020b or higher
% author:cuixingxing
% email: cuixingxing150@gmail.com
% 2021.8.11 create
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

%% preprocess table type
imagesTable = renamevars(imagesTable,'id','image_id');
imagesTable = movevars(imagesTable,'image_id','Before','license');
imagesTable = sortrows(imagesTable,'image_id');
allAnnotations = removevars(allAnnotations,'id');
allAnnotations = sortrows(allAnnotations,'image_id');
allGroupAnnotations = rowfun(@groupFcn,allAnnotations,... % or findgroups/splitapply
    'GroupingVariable','image_id',...
    'OutputVariableName',"captions");

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
captions = data.captions{1};

outputdata{1} =oriImg;
outputdata{2} =captions;
end

function captions = groupFcn(caption)
captions = {caption};
end

