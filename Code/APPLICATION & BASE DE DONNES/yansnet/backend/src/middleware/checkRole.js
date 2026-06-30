module.exports = (...allowedRoles) => {
    return (req, res, next) => {
        if (!req.user || !req.user.role) {
            return res.status(403).json({ error: 'Rôle non défini' });
        }
        if (allowedRoles.includes(req.user.role)) {
            next();
        } else {
            res.status(403).json({ error: 'Permission refusée. Rôle insuffisant.' });
        }
    };
};