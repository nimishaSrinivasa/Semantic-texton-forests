classdef DecisionTree < handle
    properties(Constant = true)
        DIRICHLET = 1e-4;
    end
    properties(SetAccess = 'private') % fields with default vals
        maxDepth = 10;
        numFeature = 400;
        numThreshold = 5;
        factory = {'addTwo', 'subAbs', 'sub', 'unary'};
        labelWeights;
        root;
        numNodes = 1;
        numClass = 0;
    end
    
    methods(Static)

    end
    %%%%%%%%%% Public Methods %%%%%%%%%%
    methods        
        function DT = DecisionTree(maxDepth, numFeature, numThreshold, ...
                                   factory, labelWeights)
            if nargin > 0
                DT.maxDepth = maxDepth;
                DT.numFeature = numFeature;
                DT.numThreshold = numThreshold;
                DT.factory = factory;
                DT.labelWeights = labelWeights;
                DT.numClass = length(labelWeights);
            end
        end
        
        function DT = trainDepthFirst(DT, patches, labels)
            % Reset the tree
            DT.numNodes = 1;
            DT.root = DT.computeDepthFirst(TreeNode(), patches, labels, 0);            
        end
        
        % fill the tree with all of training data
        function fillAll(DT, patches, labels)
            DT.fill(DT.root, patches, labels);
        end              
        
        function normalizeAll(DT)
            DT.normalize(DT.root);
        end              

% data is boxSize x boxSize x N x 3
        function dist = classify(DT, data)
            dist = zeros(size(data, 3), DT.numClass);
            ids = [1:size(data,3)];
            dist = DT.findLeafDist(DT.root, data, dist, ids);
        end
        
        function bost = computeBost(DT, data)
            bost = sparse(numNodes, 1);
            bost = DT.findCounts(DT.root, bost, data);
        end
        
        function count = factoryFrequency(DT)
            count = zeros(length(DT.factory), 1);
            count = DT.countSplitMethod(DT.root, count);
        end
        % % pre-order traversal

        % function save(DT, fname)
        %     DT = printNode(root)
        % end
    end 
    %%%%%%%%%% end of Public methods %%%%%%%%%%
    
    %%%%%%%%%% Private methods %%%%%%%%%%
    methods(Access=private)
        %%%%%%%%%% for learning a tree %%%%%%%%%%
        function node = computeDepthFirst(DT, node, patches, labels, depth)
            if isempty(labels), node=[];, end
            if depth == DT.maxDepth || numel(unique(labels))==0
                classDist = zeros(DT.numClass, 1); % will fill this out later
                node = TreeNode(classDist, DT.numNodes, depth);
                DT.numNodes = DT.numNodes + 1;
                return;
            end
            % if not leaf, find the best split
            bestScore = -Inf; bestDecider = [];
            numFactory = numel(DT.factory);
            fprintf('computing the best feature split for node %d\n', ...
                    DT.numNodes);
            for i = 1:DT.numFeature
                method = mod(i, numFactory)+1; %DT.factory{mod(i, numFactory)+1};
                [values, decider] = computeFeature(patches, method);
                [score, threshold] = DT.computeBestThreshold(values, labels);
                if score > bestScore
                    bestScore = score;
                    bestDecider = decider;
                    bestDecider.threshold = threshold;
                end            
            end            
            % housekeeping
            node.distribution = zeros(DT.numClass,1);
            node.id = DT.numNodes;
            node.level = depth;
            DT.numNodes = DT.numNodes + 1;
            node.decider = bestDecider;
            % do the split
            [values, ~] = computeFeature(patches, bestDecider);
            toLeft = values < bestDecider.threshold;
            node.left = DT.computeDepthFirst(TreeNode(), ...
                                             patches(:, :, toLeft, :), ...
                                             labels(toLeft), depth+1);
            node.right = DT.computeDepthFirst(TreeNode(), ...
                                              patches(:, :, ~toLeft, :), ...
                                              labels(~toLeft), depth+1);
        end
        
        function [bestScore, bestThreshold] = computeBestThreshold(DT,values, labels)
            % candidate threshold sampled from this values gaussian
            thresholds = randn(DT.numThreshold, 1).*std(values) + mean(values);
            N = numel(values);
            infogains = ones(DT.numThreshold, 1)*-Inf;

            for i = 1:DT.numThreshold
                toLeft = values < thresholds(i);
                numL = numel(labels(toLeft)) + DT.DIRICHLET;
                numR = numel(labels(~toLeft)) + DT.DIRICHLET;
                LDist = 1/numL.*(hist(labels(toLeft), 1:DT.numClass) ...
                                 + DT.DIRICHLET./DT.numClass);
                RDist = 1/numR.*(hist(labels(~toLeft), 1:DT.numClass) ...
                                 + DT.DIRICHLET./DT.numClass);
                % calc entropy
                EL = -sum(LDist.*log2(LDist));
                ER = -sum(RDist.*log2(RDist));
                infogains(i) = -1/N*(numL*EL + numR*ER);
            end
            [bestScore, bestind] = max(infogains);
            bestThreshold = thresholds(bestind);
        end
        
        % computes the expected gain in information 
        function [E1, E2] = entropy(h1, h2)
            E1 = 0; E2 = 0;
            for i=1:numel(h1)
                E1 = E1 - h1(i)*log2(h1(i));
                E2 = E2 - h2(i)*log2(h2(i));
            end
        end

        %%fill the tree with data to build distributions at each leaf
        function fill(DT, node, patches, labels)
            node.distribution = node.distribution + ...
                   hist(labels, 1:DT.numClass)'.*DT.labelWeights; 
            if ~node.isLeaf
                [values, ~] = computeFeature(patches, node.decider);
                toLeft = values < node.decider.threshold;
                if sum(toLeft)~=0, DT.fill(node.left, patches(:, :, toLeft, :), ...
                                               labels(toLeft)); end
                if sum(toLeft)~=length(labels), DT.fill(node.right, patches(:, :, ~toLeft, :), ...
                                                labels(~toLeft)); end
            end
        end
        
        function normalize(DT, node)
        % normalize to one with dirichlet prior
            node.distribution = (node.distribution + (DT.DIRICHLET./DT.numClass))./...
                                (sum(node.distribution) + DT.DIRICHLET);
            if ~node.isLeaf
                DT.normalize(node.left);
                DT.normalize(node.right);
            end
        end
        
        function dist = findLeafDist(DT, node, data, dist, ids)
            if node.isLeaf
                dist(ids, :) = node.distribution;
                return
            end
            [values, ~] = computeFeature(data, node.decider);
            toLeft = values < node.decider.threshold;
            
            if sum(toLeft) ~= 0
                dist = DT.findLeafDist(node.left, ...
                                           patches(:, :, toLeft, :), ...
                                           dist(toLeft, :), ids(toLeft));
            end
            if sum(toLeft)~=size(patches, 3)
                dist = DT.findLeafDist(node.right, ...
                                           patches(:, :, ~toLeft, :), ...
                                           dist(~toLeft, :), ids(~toLeft));
            end
        end
        
        function bost = findCounts(DT, node, bost, data)
           % update the count by the total number of data that
           % fellin there
            bost(node.id) = numel(data);
            if ~node.isLeaf
                [values, ~] = computeFeature(data, node.decider);
                toLeft = values < node.decider.threshold;
                leftData = data(toLeft);
                rightData = data(~toLeft);
                if ~isempty(leftData)
                    bost = DT.findCounts(node.left, bost, leftData);
                end
                if ~isempty(rightData)
                    bost = bost + DT.findCounts(node.right, bost, rightData);
                end                
            end
        end

        function count = countSplitMethod(DT, node, count)
            if node.isLeaf, return; end
            switch node.decider.method
              case 'addTwo'
                count(1) = count(1) + 1;              
              case 'subAbs'
                count(2) = count(2) + 1;
              case 'sub'
                count(3) = count(3) + 1;
              case 'unary'
                count(4) = count(4) + 1;
            end
            count = DT.countSplitMethod(node.left, count);
            count = count + DT.countSplitMethod(node.right, count);
        end        
    end    
    %%%%%%%%%% end of Private methods %%%%%%%%%%        
end

    
    
