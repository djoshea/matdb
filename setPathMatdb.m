function setPathMatdb()
    % requires matlab-utils to be on the path already
    matDbRoot = pathToThisFile(); 
    fprintf('Path: Adding matdb at %s\n', matDbRoot);
    addPathRecursive(matDbRoot);
end
