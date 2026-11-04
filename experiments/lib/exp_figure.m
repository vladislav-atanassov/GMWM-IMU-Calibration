function exp_figure(fig, name)
% Saves fig to the run's outputs as name.png, light whatever the desktop theme, since
% R2025a figures follow it even in batch mode
if ~isMATLABReleaseOlderThan("R2025a")
    theme(fig, "light");
end
exportgraphics(fig, fullfile(getenv("EXP_OUT"), name + ".png"), "Resolution", 150);
end
